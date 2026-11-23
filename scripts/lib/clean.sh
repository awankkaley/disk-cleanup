#!/bin/bash
# The clean command: validates the token, then removes what was requested.

readonly TOOL_TIMEOUT_SECONDS=600
readonly DOCKER_RECLAIMED_LABEL="Total reclaimed space:"
# shellcheck disable=SC2088 # printed as a literal hint, never expanded
readonly LOG_LOCATION_HINT="~/Library/Application Support/disk-cleanup/logs"

R_FREED=0
R_ERROR=""
REQUESTED=()
DELETE_REFUSED=0

# shellcheck disable=SC2034 # R_* are read by json_clean_result in output.sh
set_result() {
  R_STATUS=$1
  R_ERROR=${2:-}
}

# Compares the bytes measured before with what measure_targets finds now.
# Nothing removed means the system denied it, unless the guard itself said no.
finish_by_remainder() {
  local before=$1
  R_FREED=$((before > MEASURE_BYTES ? before - MEASURE_BYTES : 0))
  if [ "$MEASURE_COUNT" -eq 0 ]; then
    set_result cleaned
  elif [ "$R_FREED" -gt 0 ]; then
    set_result partial SOME_ITEMS_REMAIN
  elif [ "$DELETE_REFUSED" = 1 ]; then
    set_result failed GUARD_REFUSED
  else
    set_result skipped_no_permission PERMISSION_DENIED
  fi
}

delete_targets() {
  local target
  for target in "${TARGETS[@]}"; do
    guarded_delete "$1" "$target"
    [ $? -ne "$GUARD_REFUSED" ] || DELETE_REFUSED=1
  done
}

# clean_dirs ID MODE...: every target goes through the guard once per mode.
clean_dirs() {
  local before mode
  if category_is_running; then
    set_result skipped_running APP_RUNNING
    return 0
  fi
  resolve_targets "$1"
  if [ "${#TARGETS[@]}" -eq 0 ]; then
    set_result not_found NOT_FOUND
    [ "$TARGETS_DENIED" = 1 ] && set_result skipped_no_permission PERMISSION_DENIED
    return 0
  fi
  measure_targets
  before=$MEASURE_BYTES
  shift
  for mode in "$@"; do delete_targets "$mode"; done
  measure_targets
  finish_by_remainder "$before"
}

# The root may be an allowed root itself (the temp dir), which the guard never
# accepts as a target, so each first-level entry is handed over separately.
clean_aged() {
  local root before entry
  root=$(aged_root "$1")
  if [ -z "$root" ] || ! is_real_dir "$root" || ! can_list "$root"; then
    set_result not_found NOT_FOUND
    return 0
  fi
  TARGETS=("$root")
  measure_targets "$OPT_MIN_AGE"
  before=$MEASURE_BYTES
  while IFS= read -r -d '' entry; do
    if [ -d "$entry" ]; then
      guarded_delete old-files "$entry" "$OPT_MIN_AGE"
    else
      guarded_delete file "$entry"
    fi
  done < <(find -P "$root" -xdev -mindepth 1 -maxdepth 1 \
    \( -type d -o -type f -mtime "+$OPT_MIN_AGE" \) -print0 2> /dev/null)
  measure_targets "$OPT_MIN_AGE"
  finish_by_remainder "$before"
}

# Runs the official command only under plan "command"; a failing command and
# plan "delete" both end in the guarded delete of the default folders.
clean_tool() {
  local before tool_status=0
  tool_plan "$1" || return 0
  case "$TOOL_PLAN" in
    absent) set_result not_found NOT_FOUND ;;
    custom) set_result unavailable CUSTOM_LOCATION ;;
    unavailable) set_result unavailable TOOL_UNAVAILABLE ;;
  esac
  case "$TOOL_PLAN" in command | delete) ;; *) return 0 ;; esac
  measure_targets
  before=$MEASURE_BYTES
  if [ "$TOOL_PLAN" = "command" ]; then
    log_note "official cleaning command run for $1"
    run_tool "$TOOL_TIMEOUT_SECONDS" "${TOOL_COMMAND[@]}" > /dev/null
    tool_status=$?
    if [ "$tool_status" -eq 0 ] || ! fallback_delete_possible; then
      measure_targets
      R_FREED=$((before > MEASURE_BYTES ? before - MEASURE_BYTES : 0))
      set_result cleaned
      [ "$tool_status" -eq 0 ] || set_result failed TOOL_FAILED
      return 0
    fi
  fi
  delete_targets contents
  measure_targets
  finish_by_remainder "$before"
}

docker_reclaimed_bytes() {
  awk -v label="$DOCKER_RECLAIMED_LABEL" '
    index($0, label) == 1 {
      value = $NF; unit = value; sub(/^[0-9.]+/, "", unit)
      factor = 1
      if (unit == "kB") factor = 1e3
      if (unit == "MB") factor = 1e6
      if (unit == "GB") factor = 1e9
      if (unit == "TB") factor = 1e12
      printf "%.0f", (value + 0) * factor
    }'
}

clean_docker() {
  local report bytes
  docker_probe
  if [ "$DOCKER_STATE" = "not_found" ]; then
    set_result not_found NOT_FOUND
    return 0
  fi
  if [ "$DOCKER_STATE" != "ready" ]; then
    set_result unavailable TOOL_UNAVAILABLE
    return 0
  fi
  log_note "docker image prune run"
  if ! report=$(run_tool "$TOOL_TIMEOUT_SECONDS" docker image prune -f); then
    set_result failed TOOL_FAILED
    return 0
  fi
  bytes=$(printf '%s\n' "$report" | docker_reclaimed_bytes)
  is_uint "$bytes" && R_FREED=$bytes
  set_result cleaned
}

clean_simulators() {
  local before
  if ! simulators_available; then
    set_result not_found NOT_FOUND
    return 0
  fi
  resolve_targets "$1"
  measure_targets
  before=$MEASURE_BYTES
  log_note "simctl delete unavailable run"
  if ! run_tool "$TOOL_TIMEOUT_SECONDS" xcrun simctl delete unavailable > /dev/null; then
    set_result failed TOOL_FAILED
    return 0
  fi
  measure_targets
  R_FREED=$((before > MEASURE_BYTES ? before - MEASURE_BYTES : 0))
  set_result cleaned
}

clean_category() {
  category_lookup "$1" || return 1
  R_FREED=0
  DELETE_REFUSED=0
  set_result failed INTERNAL
  case "$CAT_KIND" in
    dirs) clean_dirs "$1" contents ;;
    subdirs) clean_dirs "$1" contents empty-dir ;;
    aged) clean_aged "$1" ;;
    tool) clean_tool "$1" ;;
    docker) clean_docker ;;
    simulators) clean_simulators "$1" ;;
    projects) clean_projects ;;
  esac
  return 0
}

# Splits "a,b,a" into the REQUESTED array without duplicates.
parse_categories() {
  local rest=$1 item seen=","
  REQUESTED=()
  while [ -n "$rest" ]; do
    item=${rest%%,*}
    case "$rest" in *,*) rest=${rest#*,} ;; *) rest="" ;; esac
    [ -n "$item" ] || continue
    category_lookup "$item" || fail UNKNOWN_CATEGORY
    case "$seen" in *",$item,"*) continue ;; esac
    seen="$seen$item,"
    REQUESTED+=("$item")
  done
  [ "${#REQUESTED[@]}" -gt 0 ] || fail USAGE
}

# shellcheck disable=SC2034,SC2153 # ST_* come from state.sh, OPT_* go to scan.sh and projects.sh
validate_clean_request() {
  local now age id
  [ -n "$OPT_TOKEN" ] || fail TOKEN_MISSING
  is_token "$OPT_TOKEN" && state_read && [ "$OPT_TOKEN" = "$ST_TOKEN" ] || fail TOKEN_INVALID
  now=$(date +%s)
  age=$((now - ST_EPOCH))
  [ "$age" -ge 0 ] || fail TOKEN_INVALID
  if [ "$age" -ge "$TOKEN_TTL_SECONDS" ]; then
    state_consume
    fail TOKEN_EXPIRED
  fi
  for id in "${REQUESTED[@]}"; do
    [ "$id" = "$TRASH_CATEGORY" ] && [ "$OPT_EMPTY_TRASH" = 0 ] && fail TRASH_FLAG_REQUIRED
    [ "$id" = "$DEEP_ONLY_CATEGORY" ] && [ "$ST_DEEP" = 0 ] && fail DEEP_SCAN_REQUIRED
    case ",$ST_OK," in *",$id,"*) ;; *) fail CATEGORY_NOT_IN_SCAN ;; esac
  done
  OPT_MIN_AGE=$((10#$ST_MIN_AGE))
  OPT_DEEP=$ST_DEEP
  OPT_PROJECTS_DIR=$ST_PROJECTS_DIR
}

run_clean() {
  local id free_before free_after body="" separator="" total=0 log_written=0 hint='null'
  validate_clean_request
  state_consume || fail INTERNAL
  if [ "$OPT_LOG" = 1 ] && log_open; then
    log_written=1
    hint="\"$LOG_LOCATION_HINT\""
  fi
  free_before=$(disk_bytes)
  is_uint "${free_before#* }" || free_before=0
  for id in "${REQUESTED[@]}"; do
    clean_category "$id" || fail INTERNAL
    is_uint "$R_FREED" || R_FREED=0
    total=$((total + R_FREED))
    body="$body$separator$(json_clean_result)"
    separator=","
  done
  free_after=$(disk_bytes)
  is_uint "${free_after#* }" || free_after=0
  emit_document "$(
    printf '{"schema_version":%d,"command":"clean","platform":"%s","disk_before":{"free_bytes":%s},' \
      "$SCHEMA_VERSION" "$PLATFORM" "${free_before#* }"
    printf '"disk_after":{"free_bytes":%s},"freed_total_bytes":%s,"results":[%s],' \
      "${free_after#* }" "$total" "$body"
    printf '"log_file_written":%s,"log_location_hint":%s}' "$(json_bool "$log_written")" "$hint"
  )"
}
