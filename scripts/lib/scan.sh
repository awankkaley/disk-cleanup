#!/bin/bash
# The scan command: measures every category, never deletes.

readonly SIMCTL_PROBE_SECONDS=30
readonly UNKNOWN=""
readonly BYTES_PER_GB=1073741824

R_STATUS=""
R_SIZE=0
R_COUNT=0
R_EXTRA=""

aged_root() {
  case "$1" in
    temp-files) printf '%s' "$TEMP_ROOT" ;;
    logs) printf '%s' "$LIBRARY/Logs" ;;
  esac
}

scan_dirs() {
  resolve_targets "$1"
  if [ "${#TARGETS[@]}" -eq 0 ]; then
    [ "$TARGETS_DENIED" = 1 ] && R_STATUS=skipped_no_permission
    return 0
  fi
  measure_targets
  R_SIZE=$MEASURE_BYTES
  R_COUNT=$MEASURE_COUNT
  if category_is_running; then
    R_STATUS=skipped_running
  elif [ "$MEASURE_COUNT" -gt 0 ]; then
    R_STATUS=ok
  elif [ "$TARGETS_DENIED" = 1 ]; then
    R_STATUS=skipped_no_permission
  else
    R_STATUS=empty
  fi
}

scan_aged() {
  local root
  root=$(aged_root "$1")
  [ -n "$root" ] && is_real_dir "$root" || return 0
  if ! can_list "$root"; then
    R_STATUS=skipped_no_permission
    return 0
  fi
  TARGETS=("$root")
  measure_targets "$OPT_MIN_AGE"
  R_SIZE=$MEASURE_BYTES
  R_COUNT=$MEASURE_COUNT
  R_STATUS=empty
  [ "$MEASURE_COUNT" -gt 0 ] && R_STATUS=ok
}

scan_tool() {
  tool_plan "$1" || return 0
  R_SIZE=$UNKNOWN
  R_COUNT=$UNKNOWN
  R_STATUS=empty
  case "$TOOL_PLAN" in
    absent)
      R_STATUS=not_found R_SIZE=0 R_COUNT=0
      return 0
      ;;
    custom | unavailable)
      R_STATUS=unavailable
      return 0
      ;;
  esac
  if [ "$TOOL_SIZE_KNOWN" = 0 ]; then
    targets_hold_files && R_STATUS=ok
    return 0
  fi
  measure_targets
  R_SIZE=$MEASURE_BYTES
  R_COUNT=$MEASURE_COUNT
  [ "$MEASURE_COUNT" -gt 0 ] && R_STATUS=ok
}

# Sets DOCKER_STATE to not_found, unavailable or ready (with DOCKER_COUNT).
docker_probe() {
  local images
  DOCKER_STATE=not_found
  DOCKER_COUNT=0
  tool_present docker || return 0
  DOCKER_STATE=unavailable
  run_tool "$TOOL_PROBE_SECONDS" docker info > /dev/null || return 0
  images=$(run_tool "$TOOL_PROBE_SECONDS" docker images -f dangling=true -q) || return 0
  DOCKER_COUNT=$(printf '%s\n' "$images" | awk 'NF { count++ } END { printf "%d", count }')
  is_uint "$DOCKER_COUNT" || return 0
  DOCKER_STATE=ready
}

scan_docker() {
  R_SIZE=$UNKNOWN
  R_COUNT=$UNKNOWN
  docker_probe
  if [ "$DOCKER_STATE" != "ready" ]; then
    R_STATUS=$DOCKER_STATE
    return 0
  fi
  R_COUNT=$DOCKER_COUNT
  R_STATUS=empty
  [ "$DOCKER_COUNT" -gt 0 ] && R_STATUS=ok
}

simulators_available() {
  tool_present xcrun && run_tool "$SIMCTL_PROBE_SECONDS" xcrun --find simctl > /dev/null
}

scan_simulators() {
  local listing count
  R_SIZE=$UNKNOWN
  R_COUNT=$UNKNOWN
  simulators_available || return 0
  if ! listing=$(run_tool "$SIMCTL_PROBE_SECONDS" xcrun simctl list devices unavailable); then
    R_STATUS=unavailable
    return 0
  fi
  count=$(printf '%s\n' "$listing" | awk '/\([0-9A-Fa-f-]+\)/ { count++ } END { printf "%d", count }')
  is_uint "$count" || count=0
  R_COUNT=$count
  R_STATUS=empty
  [ "$count" -gt 0 ] && R_STATUS=ok
}

# shellcheck disable=SC2034 # R_* are read by json_scan_category in output.sh
scan_category() {
  category_lookup "$1" || return 1
  R_STATUS=not_found
  R_SIZE=0
  R_COUNT=0
  R_EXTRA=""
  case "$CAT_KIND" in
    dirs | subdirs) scan_dirs "$1" ;;
    aged) scan_aged "$1" ;;
    tool) scan_tool "$1" ;;
    docker) scan_docker ;;
    simulators) scan_simulators ;;
    projects) scan_projects ;;
  esac
  return 0
}

# suggestion_json TARGET_BYTES CANDIDATES: CANDIDATES holds one "cost size id"
# line per category that may be suggested. Cheapest rebuild first, then the
# largest, until the target is covered; ties keep the catalog order.
suggestion_json() {
  printf '%s\n' "$2" | awk -v target="$1" '
    NF == 3 { count++; cost[count] = $1; size[count] = $2; id[count] = $3 }
    function precedes(a, b) {
      return cost[a] < cost[b] || (cost[a] == cost[b] && size[a] > size[b])
    }
    END {
      for (taken = 0; taken < count && total < target; taken++) {
        best = 0
        for (i = 1; i <= count; i++)
          if (!(i in used) && (best == 0 || precedes(i, best))) best = i
        used[best] = 1
        total += size[best]
        ids = ids (taken ? "," : "") "\"" id[best] "\""
      }
      printf "{\"target_bytes\":%.0f,\"category_ids\":[%s],\"total_bytes\":%.0f,\"reaches_target\":%s}", \
        target, ids, total, (total >= target ? "true" : "false")
    }'
}

# Adds the scanned category to SUGGEST_CANDIDATES when it may be suggested.
note_suggestion_candidate() {
  [ "$R_STATUS" = "ok" ] && [ "$CAT_RISK" = "safe" ] || return 0
  is_uint "$R_SIZE" && [ "$R_SIZE" -gt 0 ] || return 0
  SUGGEST_CANDIDATES="$SUGGEST_CANDIDATES$CAT_COST $R_SIZE $CAT_ID"$'\n'
}

scan_suggestion() {
  [ -n "$OPT_TARGET_GB" ] || return 0
  printf ',"suggestion":%s' "$(suggestion_json "$((OPT_TARGET_GB * BYTES_PER_GB))" "$SUGGEST_CANDIDATES")"
}

run_scan() {
  local row id token disk ok_ids="" body="" separator="" recommended_total=0
  SUGGEST_CANDIDATES=""
  ensure_private_dir "$STATE_DIR" || fail INTERNAL
  disk=$(disk_bytes)
  if ! is_uint "${disk% *}" || ! is_uint "${disk#* }"; then fail INTERNAL; fi
  for row in "${CATEGORY_ROWS[@]}"; do
    id=${row%%|*}
    [ "$id" = "$DEEP_ONLY_CATEGORY" ] && [ "$OPT_DEEP" = 0 ] && continue
    scan_category "$id" || fail INTERNAL
    body="$body$separator$(json_scan_category)"
    separator=","
    note_suggestion_candidate
    [ "$R_STATUS" = "ok" ] || continue
    ok_ids="$ok_ids${ok_ids:+,}$id"
    [ "$CAT_RISK" = "safe" ] && is_uint "$R_SIZE" && recommended_total=$((recommended_total + R_SIZE))
  done
  token=$(new_token) || fail INTERNAL
  state_write "$token" "$ok_ids" || fail INTERNAL
  emit_document "$(
    printf '{"schema_version":%d,"command":"scan","platform":"%s","token":"%s","token_expires_in_seconds":%d,' \
      "$SCHEMA_VERSION" "$PLATFORM" "$token" "$TOKEN_TTL_SECONDS"
    printf '"disk":{"total_bytes":%s,"free_bytes":%s},"recommended_total_bytes":%s,"categories":[%s]%s}' \
      "${disk% *}" "${disk#* }" "$recommended_total" "$body" "$(scan_suggestion)"
  )"
}
