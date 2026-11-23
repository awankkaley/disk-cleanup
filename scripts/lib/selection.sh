#!/bin/bash
# The selection file the report's Save button puts into Downloads. Its text is
# matched against one strict pattern and never executed.

readonly SELECTION_STEM="disk-cleanup-selection"
readonly SELECTION_SUFFIX=".json"
readonly SELECTION_MAX_BYTES=1048576
readonly SELECTION_MAX_COPY_DIGITS=4
readonly SELECTION_SPACE='[[:space:]]*'
readonly SELECTION_PATTERN="^${SELECTION_SPACE}\\{${SELECTION_SPACE}\"token\"${SELECTION_SPACE}:${SELECTION_SPACE}\"([0-9a-f]{8})\"${SELECTION_SPACE},${SELECTION_SPACE}\"secret\"${SELECTION_SPACE}:${SELECTION_SPACE}\"([0-9a-f]{32})\"${SELECTION_SPACE},${SELECTION_SPACE}\"ids\"${SELECTION_SPACE}:${SELECTION_SPACE}\\[${SELECTION_SPACE}(([0-9]+${SELECTION_SPACE},${SELECTION_SPACE})*[0-9]+)?${SELECTION_SPACE}\\]${SELECTION_SPACE}\\}${SELECTION_SPACE}\$"

SELECTION_TOKEN=""
SELECTION_SECRET=""
SELECTION_IDS=""
SELECTION_FILES=()

# The fixed name, or the copies browsers make of it: "name (2).json",
# "name-2.json", "name 2.json".
is_selection_name() {
  local middle digits
  case "$1" in
    "$SELECTION_STEM$SELECTION_SUFFIX") return 0 ;;
    "$SELECTION_STEM"?*"$SELECTION_SUFFIX") ;;
    *) return 1 ;;
  esac
  middle=${1#"$SELECTION_STEM"}
  middle=${middle%"$SELECTION_SUFFIX"}
  case "$middle" in
    " ("*")") digits=${middle#" ("} digits=${digits%")"} ;;
    "-"* | " "*) digits=${middle#?} ;;
    *) return 1 ;;
  esac
  is_uint "$digits" && [ "${#digits}" -le "$SELECTION_MAX_COPY_DIGITS" ]
}

# Loads SELECTION_TOKEN, SELECTION_SECRET and SELECTION_IDS ("1,5,9") from
# FILE; fails unless the whole content is
# {"token":"<8 hex>","secret":"<32 hex>","ids":[<numbers>]}.
selection_parse() {
  local file=$1 size content
  SELECTION_TOKEN="" SELECTION_SECRET="" SELECTION_IDS=""
  [ -f "$file" ] && [ ! -L "$file" ] || return 1
  size=$(stat -f '%z' "$file" 2> /dev/null) || return 1
  is_uint "$size" && [ "$size" -le "$SELECTION_MAX_BYTES" ] || return 1
  content=$(< "$file") 2> /dev/null || return 1
  [[ $content =~ $SELECTION_PATTERN ]] || return 1
  SELECTION_TOKEN=${BASH_REMATCH[1]}
  SELECTION_SECRET=${BASH_REMATCH[2]}
  SELECTION_IDS=${BASH_REMATCH[3]//[[:space:]]/}
}

# selection_matches FILE TOKEN SECRET: FILE is a well-formed selection that
# names this review token and carries this review's selection secret.
selection_matches() {
  is_token "${2:-}" && is_secret "${3:-}" && selection_parse "$1" || return 1
  [ "$SELECTION_TOKEN" = "$2" ] && [ "$SELECTION_SECRET" = "$3" ]
}

# Finds the newest selection file for TOKEN and SECRET directly inside
# Downloads and loads its ids. SELECTION_FILES collects every file saved for
# this review. Returns 1 when no selection file exists, 2 when none of them
# is usable; files that do not match are left where they are.
selection_locate() {
  local token=$1 secret=$2 folder="$HOME_PHYS/$DOWNLOADS_FOLDER" file mtime newest=-1 ids="" named=0
  SELECTION_FILES=()
  is_real_dir "$folder" && can_list "$folder" || return 1
  while IFS= read -r -d '' file; do
    is_selection_name "${file##*/}" || continue
    named=1
    selection_matches "$file" "$token" "$secret" || continue
    SELECTION_FILES+=("$file")
    mtime=$(stat -f '%m' "$file" 2> /dev/null) || continue
    is_uint "$mtime" && [ "$mtime" -gt "$newest" ] || continue
    newest=$mtime
    ids=$SELECTION_IDS
  done < <(find -P "$folder" -xdev -mindepth 1 -maxdepth 1 -type f \
    -name "$SELECTION_STEM*$SELECTION_SUFFIX" -print0 2> /dev/null)
  [ "$named" = 1 ] || return 1
  [ "$newest" -ge 0 ] || return 2
  SELECTION_IDS=$ids
}

# selection_discard TOKEN SECRET: removes the selection files of the consumed
# review; each one goes through the guard, which reads the file again.
selection_discard() {
  local file
  [ "${#SELECTION_FILES[@]}" -gt 0 ] || return 0
  for file in "${SELECTION_FILES[@]}"; do
    guarded_delete selection "$file" "$1" "$2"
  done
}
