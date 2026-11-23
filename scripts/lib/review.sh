#!/bin/bash
# The review command: lists large files and old downloads for the human-only
# report. Only counts and totals ever reach stdout. Nothing is moved here.

readonly REVIEW_FORMAT=1
readonly REVIEW_MANIFEST_NAME="review-manifest"
readonly REVIEW_REPORT_NAME="review.html"
readonly REVIEW_MAX_ITEMS=500
readonly REVIEW_MAX_ID_DIGITS=3
readonly REVIEW_GROUP_LARGE="large-files"
readonly REVIEW_GROUP_DOWNLOADS="old-downloads"
readonly REVIEW_LABEL_LARGE="Large files"
readonly REVIEW_LABEL_DOWNLOADS="Old items in Downloads"
# shellcheck disable=SC2088 # printed as a literal hint, never expanded
readonly REVIEW_REPORT_HINT="~/Library/Application Support/disk-cleanup/review.html"
readonly REVIEW_SELECTION_HINT="Downloads/disk-cleanup-selection.json"
readonly REVIEW_OPEN_SECONDS=15
readonly BYTES_PER_MB=1048576
# Allocation can exceed the logical size by a little, so find pre-selects with
# this much slack and the exact test runs on the allocated size.
readonly REVIEW_SIZE_SLACK_BLOCKS=2048
readonly REVIEW_DENIED_MARK="-1"
readonly TAB=$'\t'
readonly CONTROL_CHARACTER_PATTERN='*[[:cntrl:]]*'
readonly HIDDEN_PATTERN='.*'
# Folders the walk never enters and review-apply never accepts: top-level
# system folders, dependency folders, and packages that only look like folders.
readonly REVIEW_PRUNED_TOP=("Library" "AppData")
readonly REVIEW_PRUNED_NAME="node_modules"
readonly REVIEW_BUNDLE_SUFFIXES=(
  "app" "photoslibrary" "musiclibrary" "tvlibrary" "imovielibrary" "fcpbundle"
  "logicx" "band" "sparsebundle" "vmwarevm" "pvm" "utm" "bundle" "framework"
  "xcodeproj" "lrcat" "lrdata"
)

REVIEW_MANIFEST=""
REVIEW_REPORT=""
REVIEW_PRUNE=()
REVIEW_SUMMARY=()
FIELDS=()
RV_TOKEN=""
RV_EPOCH=""
RV_ALLOCATED=()
RV_LOGICAL=()
RV_MTIME=()
RV_PATH=()

review_paths() {
  REVIEW_MANIFEST="$STATE_DIR/$REVIEW_MANIFEST_NAME"
  REVIEW_REPORT="$STATE_DIR/$REVIEW_REPORT_NAME"
}

review_prune_expression() {
  local entry
  REVIEW_PRUNE=(-name "$HIDDEN_PATTERN" -o -iname "$REVIEW_PRUNED_NAME")
  for entry in "${REVIEW_PRUNED_TOP[@]}"; do
    REVIEW_PRUNE+=(-o -ipath "./$entry")
  done
  for entry in "${REVIEW_BUNDLE_SUFFIXES[@]}"; do
    REVIEW_PRUNE+=(-o -iname "*.$entry")
  done
}

# The single walk of the home directory. Prints "blocks size mtime ./path" for
# every candidate; a last line marks folders that could not be read.
review_walk() {
  local min_blocks=$((OPT_MIN_SIZE_MB * BYTES_PER_MB / BLOCK_BYTES - REVIEW_SIZE_SLACK_BLOCKS))
  review_prune_expression
  cd "$HOME_PHYS" 2> /dev/null || return 1
  {
    find -P . -xdev -mindepth 1 -path "$CONTROL_CHARACTER_PATTERN" -prune \
      -o -type d \( "${REVIEW_PRUNE[@]}" \) -prune \
      -o -type f ! -name "$HIDDEN_PATTERN" ! -name "$SELECTION_STEM*$SELECTION_SUFFIX" \
      \( -size "+$min_blocks" -o \( -path "./$DOWNLOADS_FOLDER/*" ! -path "./$DOWNLOADS_FOLDER/*/*" \) \) \
      -exec stat -f '%b %z %m %N' {} + 2>&1 >&3 3>&- |
      awk -v mark="$REVIEW_DENIED_MARK" '
        /(Permission denied|Operation not permitted)$/ { denied = 1 }
        END { if (denied) print mark }'
  } 3>&1
}

# Turns walk lines into "allocated<TAB>size<TAB>mtime<TAB>group<TAB>/path".
review_classify() {
  awk -v min_bytes="$((OPT_MIN_SIZE_MB * BYTES_PER_MB))" -v block="$BLOCK_BYTES" \
    -v now="$1" -v old_seconds="$((OPT_DOWNLOADS_AGE * SECONDS_PER_DAY))" \
    -v large="$REVIEW_GROUP_LARGE" -v old="$REVIEW_GROUP_DOWNLOADS" \
    -v downloads="/$DOWNLOADS_FOLDER/" -v mark="$REVIEW_DENIED_MARK" '
    $0 == mark { print; next }
    !/^[0-9]+ [0-9]+ [0-9]+ \.\/./ || /\t/ { next }
    {
      path = $0
      sub(/^[0-9]+ [0-9]+ [0-9]+ \./, "", path)
      bytes = $1 * block
      inside = substr(path, length(downloads) + 1)
      if ($1 == 0) next
      if (bytes >= min_bytes) group = large
      else if (index(path, downloads) == 1 && index(inside, "/") == 0 && now - $3 >= old_seconds) group = old
      else next
      printf "%.0f\t%s\t%s\t%s\t%s\n", bytes, $2, $3, group, path
    }'
}

# Keeps the largest items, numbers them and makes the paths absolute. The
# last line is "#<TAB>found<TAB>denied<TAB>count and bytes of each group".
review_number() {
  REVIEW_HOME=$HOME_PHYS awk -F '\t' -v max="$REVIEW_MAX_ITEMS" -v mark="$REVIEW_DENIED_MARK" \
    -v large="$REVIEW_GROUP_LARGE" -v old="$REVIEW_GROUP_DOWNLOADS" '
    $1 == mark { denied = 1; next }
    NF != 5 { next }
    ++found > max { next }
    {
      count[$4]++
      bytes[$4] += $1
      printf "%d\t%s\t%s\t%s\t%s\t%s%s\n", found, $1, $2, $3, $4, ENVIRON["REVIEW_HOME"], $5
    }
    END {
      printf "#\t%d\t%d\t%d\t%.0f\t%d\t%.0f\n", found, denied, \
        count[large], bytes[large], count[old], bytes[old]
    }'
}

review_collect() {
  (review_walk) | review_classify "$1" | sort -t "$TAB" -k 1,1nr -k 5 | review_number
}

# Splits a tab separated line into the FIELDS array.
split_tabs() {
  local rest=$1
  FIELDS=()
  while :; do
    case "$rest" in
      *"$TAB"*)
        FIELDS+=("${rest%%"$TAB"*}")
        rest=${rest#*"$TAB"}
        ;;
      *)
        FIELDS+=("$rest")
        return 0
        ;;
    esac
  done
}

# Splits the summary line into REVIEW_SUMMARY: found, denied, then count and
# bytes of the large files and of the old downloads.
review_summary_read() {
  local field
  case "$1" in "#$TAB"*) ;; *) return 1 ;; esac
  split_tabs "${1#"#$TAB"}"
  REVIEW_SUMMARY=("${FIELDS[@]}")
  [ "${#REVIEW_SUMMARY[@]}" -eq 6 ] || return 1
  for field in "${REVIEW_SUMMARY[@]}"; do is_uint "$field" || return 1; done
}

review_file_is_writable() {
  [ ! -L "$1" ] || return 1
  [ ! -e "$1" ] || [ -f "$1" ]
}

# review_manifest_write TOKEN EPOCH ITEMS
review_manifest_write() {
  ensure_private_dir "$STATE_DIR" && review_file_is_writable "$REVIEW_MANIFEST" || return 1
  (
    umask 077
    printf 'format=%s\ntoken=%s\nepoch=%s\n%s%s' "$REVIEW_FORMAT" "$1" "$2" "$3" "${3:+$'\n'}" \
      > "$REVIEW_MANIFEST"
  ) 2> /dev/null || return 1
  chmod "$PRIVATE_FILE_MODE" "$REVIEW_MANIFEST" 2> /dev/null
}

review_manifest_item() {
  local id=${1:-} index
  [ $# -eq 6 ] || return 0
  is_uint "$id" && [ "${#id}" -le "$REVIEW_MAX_ID_DIGITS" ] || return 0
  is_uint "$2" && is_uint "$3" && is_uint "$4" && [ -n "$6" ] || return 0
  index=$((10#$id))
  [ "$index" -ge 1 ] && [ "$index" -le "$REVIEW_MAX_ITEMS" ] || return 0
  RV_ALLOCATED[index]=$2
  RV_LOGICAL[index]=$3
  RV_MTIME[index]=$4
  RV_PATH[index]=$6
}

# Loads RV_* from the manifest; the content is validated, never executed.
# shellcheck disable=SC2034 # RV_* are read by apply.sh
review_manifest_read() {
  local line
  RV_TOKEN="" RV_EPOCH="" RV_ALLOCATED=() RV_LOGICAL=() RV_MTIME=() RV_PATH=()
  [ -f "$REVIEW_MANIFEST" ] && [ ! -L "$REVIEW_MANIFEST" ] && [ -O "$REVIEW_MANIFEST" ] || return 1
  [ ! -L "$STATE_DIR" ] || return 1
  while IFS= read -r line; do
    case "$line" in
      token=*) RV_TOKEN=${line#token=} ;;
      epoch=*) RV_EPOCH=${line#epoch=} ;;
      [0-9]*"$TAB"*)
        split_tabs "$line"
        review_manifest_item "${FIELDS[@]}"
        ;;
    esac
  done < "$REVIEW_MANIFEST"
  is_token "$RV_TOKEN" && is_uint "$RV_EPOCH"
}

# The manifest goes first: without it the token is gone for good.
review_discard() {
  guarded_delete file "$REVIEW_MANIFEST" || return 1
  [ ! -e "$REVIEW_REPORT" ] || guarded_delete file "$REVIEW_REPORT"
  return 0
}

folder_name_is_pruned() {
  local name=$1 suffix verdict=1
  shopt -s nocasematch
  case "$name" in "$REVIEW_PRUNED_NAME") verdict=0 ;; esac
  for suffix in "${REVIEW_BUNDLE_SUFFIXES[@]}"; do
    case "$name" in *".$suffix") verdict=0 ;; esac
  done
  shopt -u nocasematch
  return "$verdict"
}

# The review guard: PATH is a plain absolute path strictly inside the home
# directory and outside everything the walk refuses to enter.
review_path_is_acceptable() {
  local relative folders folder
  case "$1" in "$HOME_PHYS"/?*) ;; *) return 1 ;; esac
  relative=${1#"$HOME_PHYS"/}
  case "$relative" in *[[:cntrl:]]*) return 1 ;; esac
  case "/$relative/" in *//* | */.*) return 1 ;; esac
  case "$relative" in */*) folders=${relative%/*} ;; *) return 0 ;; esac
  list_contains "${folders%%/*}" "${REVIEW_PRUNED_TOP[@]}" && return 1
  while [ -n "$folders" ]; do
    folder=${folders%%/*}
    case "$folders" in */*) folders=${folders#*/} ;; *) folders="" ;; esac
    folder_name_is_pruned "$folder" && return 1
  done
  return 0
}

# The only place that opens the report (tests stub the open tool on PATH).
open_report() {
  run_tool "$REVIEW_OPEN_SECONDS" open "$REVIEW_REPORT" > /dev/null
}

review_groups_json() {
  printf '"groups":[{"id":"%s","label":"%s","item_count":%s,"size_bytes":%s},' \
    "$REVIEW_GROUP_LARGE" "$REVIEW_LABEL_LARGE" "${REVIEW_SUMMARY[2]}" "${REVIEW_SUMMARY[3]}"
  printf '{"id":"%s","label":"%s","item_count":%s,"size_bytes":%s}],' \
    "$REVIEW_GROUP_DOWNLOADS" "$REVIEW_LABEL_DOWNLOADS" "${REVIEW_SUMMARY[4]}" "${REVIEW_SUMMARY[5]}"
  printf '"total_item_count":%s,"total_size_bytes":%s,' \
    "$((REVIEW_SUMMARY[2] + REVIEW_SUMMARY[4]))" "$((REVIEW_SUMMARY[3] + REVIEW_SUMMARY[5]))"
}

# emit_review TOKEN OPENED
emit_review() {
  local truncated=0 denied=""
  [ "${REVIEW_SUMMARY[0]}" -le "$REVIEW_MAX_ITEMS" ] || truncated=1
  [ "${REVIEW_SUMMARY[1]}" = 0 ] || denied=',"skipped_no_permission":true'
  emit_document "$(
    printf '{"schema_version":%d,"command":"review","platform":"%s","token":"%s","token_expires_in_seconds":%d,' \
      "$SCHEMA_VERSION" "$PLATFORM" "$1" "$REVIEW_TOKEN_TTL_SECONDS"
    review_groups_json
    printf '"truncated":%s,"report_opened":%s,"report_location_hint":"%s","selection_file_hint":"%s"%s}' \
      "$(json_bool "$truncated")" "$(json_bool "$2")" "$REVIEW_REPORT_HINT" "$REVIEW_SELECTION_HINT" "$denied"
  )"
}

run_review() {
  local now listing items="" token opened=0
  review_paths
  ensure_private_dir "$STATE_DIR" || fail INTERNAL
  now=$(date +%s)
  is_uint "$now" || fail INTERNAL
  listing=$(review_collect "$now")
  review_summary_read "${listing##*$'\n'}" || fail INTERNAL
  case "$listing" in *$'\n'*) items=${listing%$'\n'*} ;; esac
  token=$(new_token) || fail INTERNAL
  review_file_is_writable "$REVIEW_REPORT" || fail INTERNAL
  review_manifest_write "$token" "$now" "$items" || fail INTERNAL
  report_write "$token" "$items" || fail INTERNAL
  open_report && opened=1
  emit_review "$token" "$opened"
}
