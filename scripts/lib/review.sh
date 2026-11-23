#!/bin/bash
# The review command: lists large files and old downloads for the human-only
# report. Only counts and totals ever reach stdout. Nothing is moved here.

readonly REVIEW_FORMAT=2
# The manifest starts with exactly these lines, in this order; every line
# after them is an item.
readonly REVIEW_HEADER_KEYS=("format" "token" "epoch" "secret" "min_size_mb" "downloads_age_days" "integrity")
readonly DIGEST_HEX_DIGITS=64
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
# UTF-8 bytes of the characters that reorder or hide text on screen (U+202A to
# U+202E, U+2066 to U+2069, U+200E, U+200F, U+061C). A name holding one could
# show the user something other than the file it stands for, so such files
# are never offered.
readonly BIDI_CONTROL_SEQUENCES=(
  $'\xe2\x80\xaa' $'\xe2\x80\xab' $'\xe2\x80\xac' $'\xe2\x80\xad' $'\xe2\x80\xae'
  $'\xe2\x81\xa6' $'\xe2\x81\xa7' $'\xe2\x81\xa8' $'\xe2\x81\xa9'
  $'\xe2\x80\x8e' $'\xe2\x80\x8f' $'\xd8\x9c'
)
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
REVIEW_LIVE=0
RV_TOKEN=""
RV_EPOCH=""
RV_SECRET=""
RV_MIN_SIZE_MB=""
RV_DOWNLOADS_AGE=""
RV_INTEGRITY=""
RV_ITEMS=""
RV_ALLOCATED=()
RV_LOGICAL=()
RV_MTIME=()
RV_GROUP=()
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
  REVIEW_BIDI=$(printf '%s\n' "${BIDI_CONTROL_SEQUENCES[@]}") awk -v min_bytes="$((OPT_MIN_SIZE_MB * BYTES_PER_MB))" -v block="$BLOCK_BYTES" \
    -v now="$1" -v old_seconds="$((OPT_DOWNLOADS_AGE * SECONDS_PER_DAY))" \
    -v large="$REVIEW_GROUP_LARGE" -v old="$REVIEW_GROUP_DOWNLOADS" \
    -v downloads="/$DOWNLOADS_FOLDER/" -v mark="$REVIEW_DENIED_MARK" '
    BEGIN { marks = split(ENVIRON["REVIEW_BIDI"], bidi, "\n") }
    $0 == mark { print; next }
    !/^[0-9]+ [0-9]+ [0-9]+ \.\/./ || /\t/ { next }
    {
      path = $0
      sub(/^[0-9]+ [0-9]+ [0-9]+ \./, "", path)
      for (i = 1; i <= marks; i++) if (bidi[i] != "" && index(path, bidi[i])) next
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

# review_seal SECRET ITEMS: prints the SHA-256 over the secret line followed
# by the item lines. Only this text is hashed, never a file of the user.
review_seal() {
  local digest
  digest=$(printf '%s\n%s%s' "$1" "$2" "${2:+$'\n'}" | shasum -a 256)
  digest=${digest%% *}
  is_hex_of_length "$digest" "$DIGEST_HEX_DIGITS" && printf '%s' "$digest"
}

# review_manifest_write TOKEN EPOCH SECRET ITEMS
# shellcheck disable=SC2153 # OPT_* are the parsed options from cleanup.sh
review_manifest_write() {
  local digest
  ensure_private_dir "$STATE_DIR" && review_file_is_writable "$REVIEW_MANIFEST" || return 1
  digest=$(review_seal "$3" "$4") || return 1
  (
    umask 077
    printf 'format=%s\ntoken=%s\nepoch=%s\nsecret=%s\nmin_size_mb=%s\ndownloads_age_days=%s\nintegrity=%s\n%s%s' \
      "$REVIEW_FORMAT" "$1" "$2" "$3" "$OPT_MIN_SIZE_MB" "$OPT_DOWNLOADS_AGE" "$digest" "$4" "${4:+$'\n'}" \
      > "$REVIEW_MANIFEST"
  ) 2> /dev/null || return 1
  chmod "$PRIVATE_FILE_MODE" "$REVIEW_MANIFEST" 2> /dev/null
}

# review_header_assign NUMBER LINE: line NUMBER must be the header key that
# belongs at that position.
review_header_assign() {
  local key=${2%%=*} value=${2#*=}
  [ "$key" = "${REVIEW_HEADER_KEYS[$1 - 1]}" ] || return 1
  case "$key" in
    format) [ "$value" = "$REVIEW_FORMAT" ] || return 1 ;;
    token) RV_TOKEN=$value ;;
    epoch) RV_EPOCH=$value ;;
    secret) RV_SECRET=$value ;;
    min_size_mb) RV_MIN_SIZE_MB=$value ;;
    downloads_age_days) RV_DOWNLOADS_AGE=$value ;;
    integrity) RV_INTEGRITY=$value ;;
  esac
}

# The recorded options obey the same limits as the command line, so an edited
# header cannot loosen the rules below what review itself accepts.
review_header_is_valid() {
  is_token "$RV_TOKEN" && is_uint "$RV_EPOCH" && is_secret "$RV_SECRET" || return 1
  is_uint_between "$RV_MIN_SIZE_MB" "$MIN_SIZE_MB_FLOOR" "$MAX_SIZE_MB" || return 1
  is_day_count "$RV_DOWNLOADS_AGE" "$DOWNLOADS_AGE_DAYS_FLOOR" || return 1
  is_hex_of_length "$RV_INTEGRITY" "$DIGEST_HEX_DIGITS" || return 1
  RV_EPOCH=$((10#$RV_EPOCH))
  RV_MIN_SIZE_MB=$((10#$RV_MIN_SIZE_MB))
  RV_DOWNLOADS_AGE=$((10#$RV_DOWNLOADS_AGE))
}

review_manifest_item() {
  local id=${1:-} index
  [ $# -eq 6 ] || return 0
  is_uint "$id" && [ "${#id}" -le "$REVIEW_MAX_ID_DIGITS" ] || return 0
  is_uint "$2" && is_uint "$3" && is_uint "$4" && [ -n "$6" ] || return 0
  [ "$5" = "$REVIEW_GROUP_LARGE" ] || [ "$5" = "$REVIEW_GROUP_DOWNLOADS" ] || return 0
  index=$((10#$id))
  [ "$index" -ge 1 ] && [ "$index" -le "$REVIEW_MAX_ITEMS" ] || return 0
  RV_ALLOCATED[index]=$2
  RV_LOGICAL[index]=$3
  RV_MTIME[index]=$4
  RV_GROUP[index]=$5
  RV_PATH[index]=$6
}

# Loads RV_* from the manifest; the content is validated, never executed.
# RV_ITEMS keeps every line after the header exactly as read, for the seal.
# shellcheck disable=SC2034 # RV_* are read by apply.sh
review_manifest_read() {
  local line number=0
  RV_TOKEN="" RV_EPOCH="" RV_SECRET="" RV_MIN_SIZE_MB="" RV_DOWNLOADS_AGE="" RV_INTEGRITY="" RV_ITEMS=""
  RV_ALLOCATED=() RV_LOGICAL=() RV_MTIME=() RV_GROUP=() RV_PATH=()
  [ -f "$REVIEW_MANIFEST" ] && [ ! -L "$REVIEW_MANIFEST" ] && [ -O "$REVIEW_MANIFEST" ] || return 1
  [ ! -L "$STATE_DIR" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    number=$((number + 1))
    if [ "$number" -le "${#REVIEW_HEADER_KEYS[@]}" ]; then
      review_header_assign "$number" "$line" || return 1
      continue
    fi
    RV_ITEMS="$RV_ITEMS$line"$'\n'
    split_tabs "$line"
    review_manifest_item "${FIELDS[@]}"
  done < "$REVIEW_MANIFEST"
  [ "$number" -ge "${#REVIEW_HEADER_KEYS[@]}" ] && review_header_is_valid
}

# True while the item lines are the ones review wrote. This raises the bar
# for tampering; it is not a proof, because the secret sits in the same file.
review_manifest_is_sealed() {
  [ "$(review_seal "$RV_SECRET" "${RV_ITEMS%$'\n'}")" = "$RV_INTEGRITY" ]
}

# Removes the manifest and the report. Fails while the manifest is still
# there: without it the token is gone for good.
review_discard() {
  local verdict=0
  if [ -e "$REVIEW_MANIFEST" ]; then guarded_delete file "$REVIEW_MANIFEST" || verdict=1; fi
  [ ! -e "$REVIEW_REPORT" ] || guarded_delete file "$REVIEW_REPORT"
  return "$verdict"
}

# Runs at the start of every command and loads the current review. One that
# is older than its lifetime, damaged or dated in the future is discarded on
# the spot, so the file names it lists never stay on disk even when the user
# never comes back to it. REVIEW_LIVE marks a usable review; an expired one
# keeps its token in RV_TOKEN so review-apply can name the reason.
# shellcheck disable=SC2034 # REVIEW_LIVE is read by apply.sh
review_sweep() {
  local now age
  REVIEW_LIVE=0
  review_paths
  if review_manifest_read; then
    now=$(date +%s)
    age=$((now - RV_EPOCH))
    if [ "$age" -ge 0 ] && [ "$age" -lt "$REVIEW_TOKEN_TTL_SECONDS" ]; then
      REVIEW_LIVE=1
      return 0
    fi
    [ "$age" -ge 0 ] || RV_TOKEN=""
  else
    RV_TOKEN=""
  fi
  review_discard
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
  for folder in "${BIDI_CONTROL_SEQUENCES[@]}"; do
    case "$relative" in *"$folder"*) return 1 ;; esac
  done
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

# Prints true or false for a Downloads folder that exists, null when there is
# no such folder. False usually means the app lacks the system's permission.
review_downloads_readable() {
  local folder="$HOME_PHYS/$DOWNLOADS_FOLDER"
  if ! is_real_dir "$folder"; then
    printf 'null'
  elif can_list "$folder"; then
    printf 'true'
  else
    printf 'false'
  fi
}

# review_groups_json DOWNLOADS_READABLE
review_groups_json() {
  local downloads_status=ok
  [ "$1" != false ] || downloads_status=skipped_no_permission
  printf '"groups":[{"id":"%s","label":"%s","item_count":%s,"size_bytes":%s,"status":"ok"},' \
    "$REVIEW_GROUP_LARGE" "$REVIEW_LABEL_LARGE" "${REVIEW_SUMMARY[2]}" "${REVIEW_SUMMARY[3]}"
  printf '{"id":"%s","label":"%s","item_count":%s,"size_bytes":%s,"status":"%s"}],' \
    "$REVIEW_GROUP_DOWNLOADS" "$REVIEW_LABEL_DOWNLOADS" "${REVIEW_SUMMARY[4]}" "${REVIEW_SUMMARY[5]}" \
    "$downloads_status"
  printf '"total_item_count":%s,"total_size_bytes":%s,' \
    "$((REVIEW_SUMMARY[2] + REVIEW_SUMMARY[4]))" "$((REVIEW_SUMMARY[3] + REVIEW_SUMMARY[5]))"
}

# emit_review TOKEN OPENED
emit_review() {
  local truncated=0 denied="" readable
  readable=$(review_downloads_readable)
  [ "${REVIEW_SUMMARY[0]}" -le "$REVIEW_MAX_ITEMS" ] || truncated=1
  [ "${REVIEW_SUMMARY[1]}" = 0 ] && [ "$readable" != false ] || denied=',"skipped_no_permission":true'
  emit_document "$(
    printf '{"schema_version":%d,"command":"review","platform":"%s","token":"%s","token_expires_in_seconds":%d,' \
      "$SCHEMA_VERSION" "$PLATFORM" "$1" "$REVIEW_TOKEN_TTL_SECONDS"
    review_groups_json "$readable"
    printf '"truncated":%s,"report_opened":%s,"report_location_hint":"%s","selection_file_hint":"%s","downloads_readable":%s%s}' \
      "$(json_bool "$truncated")" "$(json_bool "$2")" "$REVIEW_REPORT_HINT" "$REVIEW_SELECTION_HINT" "$readable" "$denied"
  )"
}

run_review() {
  local now listing items="" token secret opened=0
  review_paths
  ensure_private_dir "$STATE_DIR" || fail INTERNAL
  now=$(date +%s)
  is_uint "$now" || fail INTERNAL
  listing=$(review_collect "$now")
  review_summary_read "${listing##*$'\n'}" || fail INTERNAL
  case "$listing" in *$'\n'*) items=${listing%$'\n'*} ;; esac
  token=$(new_token) || fail INTERNAL
  secret=$(new_secret) || fail INTERNAL
  review_file_is_writable "$REVIEW_REPORT" || fail INTERNAL
  review_manifest_write "$token" "$now" "$secret" "$items" || fail INTERNAL
  report_write "$token" "$secret" "$items" || fail INTERNAL
  open_report && opened=1
  emit_review "$token" "$opened"
}
