#!/bin/bash
# The review-apply command: moves the items the user ticked in the report to
# the Trash, after checking every one of them again.

A_SELECTED=0
A_TRASHED=0
A_TRASHED_BYTES=0
A_CHANGED=0
A_DENIED=0
A_FAILED=0
A_IGNORED=0

# The sweep at command start already loaded the review and discarded an
# expired one; the token only decides which error the caller gets.
validate_apply_request() {
  [ -n "$OPT_TOKEN" ] || fail TOKEN_MISSING
  is_token "$OPT_TOKEN" && [ "$OPT_TOKEN" = "$RV_TOKEN" ] || fail TOKEN_INVALID
  [ "$REVIEW_LIVE" = 1 ] || fail TOKEN_EXPIRED
}

load_selection() {
  selection_locate "$OPT_TOKEN" "$RV_SECRET"
  case $? in
    0) ;;
    1) fail SELECTION_NOT_FOUND ;;
    *) fail SELECTION_INVALID ;;
  esac
}

# Prints the manifest index of a selected id, or nothing when the manifest
# has no such item.
manifest_index() {
  is_uint "$1" && [ "${#1}" -le "$REVIEW_MAX_ID_DIGITS" ] || return 0
  [ -n "${RV_PATH[10#$1]:-}" ] && printf '%s' "$((10#$1))"
}

# True while the item still meets the rule of the group it was listed under,
# so a line added to the manifest cannot bring in a file review would never
# have offered. The trash routine then confirms size and time on disk.
item_still_qualifies() {
  local index=$1 now=$2 path=${RV_PATH[$1]} allocated=$((10#${RV_ALLOCATED[$1]}))
  [ "$allocated" -gt 0 ] || return 1
  case "${RV_GROUP[index]}" in
    "$REVIEW_GROUP_LARGE") [ "$allocated" -ge $((RV_MIN_SIZE_MB * BYTES_PER_MB)) ] ;;
    "$REVIEW_GROUP_DOWNLOADS")
      [ "${path%/*}" = "$HOME_PHYS/$DOWNLOADS_FOLDER" ] || return 1
      [ $((now - 10#${RV_MTIME[index]})) -ge $((RV_DOWNLOADS_AGE * SECONDS_PER_DAY)) ]
      ;;
    *) return 1 ;;
  esac
}

# shellcheck disable=SC2034 # FINDER_ENABLED is read by trash.sh
apply_item() {
  local index=$1 now=$2 path outcome
  path=${RV_PATH[index]}
  if ! review_path_is_acceptable "$path" || ! item_still_qualifies "$index" "$now"; then
    A_CHANGED=$((A_CHANGED + 1))
    return 0
  fi
  trash_file "${path%/*}" "${path##*/}" "${RV_ALLOCATED[index]}" "${RV_LOGICAL[index]}" "${RV_MTIME[index]}"
  outcome=$?
  case "$outcome" in
    "$TRASH_DONE" | "$TRASH_DONE_DIRECT")
      [ "$outcome" -eq "$TRASH_DONE" ] || FINDER_ENABLED=0
      A_TRASHED=$((A_TRASHED + 1))
      A_TRASHED_BYTES=$((A_TRASHED_BYTES + 10#${RV_ALLOCATED[index]}))
      ;;
    "$TRASH_CHANGED") A_CHANGED=$((A_CHANGED + 1)) ;;
    "$TRASH_DENIED") A_DENIED=$((A_DENIED + 1)) ;;
    *) A_FAILED=$((A_FAILED + 1)) ;;
  esac
}

# Walks the selected ids ("1,5,9"); a repeated id counts once.
apply_selection() {
  local rest=$SELECTION_IDS id index seen="," now
  now=$(date +%s)
  while [ -n "$rest" ]; do
    id=${rest%%,*}
    case "$rest" in *,*) rest=${rest#*,} ;; *) rest="" ;; esac
    case "$seen" in *",$id,"*) continue ;; esac
    seen="$seen$id,"
    A_SELECTED=$((A_SELECTED + 1))
    index=$(manifest_index "$id")
    if [ -z "$index" ]; then
      A_IGNORED=$((A_IGNORED + 1))
      continue
    fi
    apply_item "$index" "$now"
  done
}

emit_review_apply() {
  emit_document "$(
    printf '{"schema_version":%d,"command":"review-apply","platform":"%s","selected_count":%s,' \
      "$SCHEMA_VERSION" "$PLATFORM" "$A_SELECTED"
    printf '"trashed_count":%s,"trashed_bytes":%s,"skipped_changed_count":%s,' \
      "$A_TRASHED" "$A_TRASHED_BYTES" "$A_CHANGED"
    printf '"skipped_no_permission_count":%s,"failed_count":%s,"ignored_count":%s,' \
      "$A_DENIED" "$A_FAILED" "$A_IGNORED"
    printf '"disk_before":{"free_bytes":%s},"disk_after":{"free_bytes":%s},' "$1" "$2"
    printf '"space_freed_when_trash_emptied":true}'
  )"
}

# The token is consumed before anything moves, so an interrupted run can
# never be repeated with the same selection. A selection or manifest that
# fails a check moves nothing and keeps the token, so the user can retry.
run_review_apply() {
  local free_before free_after
  validate_apply_request
  review_manifest_is_sealed || fail SELECTION_INVALID
  load_selection
  review_discard || fail INTERNAL
  free_before=$(disk_bytes)
  is_uint "${free_before#* }" || free_before=0
  apply_selection
  selection_discard "$OPT_TOKEN" "$RV_SECRET"
  free_after=$(disk_bytes)
  is_uint "${free_after#* }" || free_after=0
  emit_review_apply "${free_before#* }" "${free_after#* }"
}
