#!/bin/bash
# Environment validation, the single guarded delete routine, and measuring.

readonly GUARD_REFUSED=1
readonly GUARD_INCOMPLETE=2
readonly BLOCK_BYTES=512
readonly TEMP_ROOT_PREFIX="/private/var/folders"
readonly TRASH_NAME=".Trash"
readonly TREE_MODE_NAME="node_modules"
readonly ACCOUNT_HOME_KEY="NFSHomeDirectory"
readonly PASSWD_HOME_FIELD=9

# Folders that hold user data: nothing below them is ever deleted, except a
# directory named exactly node_modules (the --deep category).
readonly PROTECTED_FOLDERS=(
  "Documents" "Desktop" "Downloads" "Pictures" "Movies" "Music" "Public"
  "Dropbox" "OneDrive" "Google Drive" "iCloud Drive" "Box" "Creative Cloud Files"
)
readonly NEVER_TOUCH=(
  "Library/Mobile Documents" "Library/CloudStorage"
  "Library/Developer/Xcode/Archives" "Library/Keychains"
  "Library/Mail" "Library/Messages"
)

HOME_PHYS=""
TEMP_ROOT=""
LOG_FILE=""
MEASURE_BYTES=0
MEASURE_COUNT=0

physical_dir() {
  [ -n "${1:-}" ] || return 1
  case "$1" in /*) ;; *) return 1 ;; esac
  [ -d "$1" ] || return 1
  (cd -P -- "$1" 2>/dev/null && pwd -P)
}

has_newline() {
  case "$1" in *$'\n'*) return 0 ;; esac
  return 1
}

home_is_sane() {
  case "$1" in /*/*) ;; *) return 1 ;; esac
  has_newline "$1" && return 1
  [ -d "$1" ] && [ -O "$1" ]
}

# The home the directory service records for this account, independent of
# $HOME; the passwd entry stands in when the local node has no answer.
account_home() {
  local user home=""
  user=$(id -un 2> /dev/null) || user=""
  if [ -n "$user" ]; then
    home=$(dscl . -read "/Users/$user" "$ACCOUNT_HOME_KEY" 2> /dev/null |
      awk -v key="$ACCOUNT_HOME_KEY:" '
        index($0, key) == 1 { $0 = substr($0, length(key) + 1) }
        { sub(/^ +/, "") }
        length($0) { print; exit }')
  fi
  [ -n "$home" ] || home=$(id -P 2> /dev/null | awk -F: -v field="$PASSWD_HOME_FIELD" 'NR == 1 { print $field }')
  physical_dir "$home"
}

# A harness that points HOME at a folder inside the real home (HOME=~/Documents)
# would move every protection along with it, so that is refused. A HOME outside
# the real home (a throwaway sandbox) protects nothing of the user and is fine.
home_is_not_redirected() {
  local real
  real=$(account_home) || return 1
  [ "$HOME_PHYS" = "$real" ] || ! path_is_under "$HOME_PHYS" "$real"
}

# The per-user temp dir on macOS always lives in /private/var/folders/x/y/T.
# The two segments are split by hand because * in a case pattern also matches /.
temp_root_has_shape() {
  local rest first second
  case "$1" in "$TEMP_ROOT_PREFIX"/*) ;; *) return 1 ;; esac
  rest=${1#"$TEMP_ROOT_PREFIX"/}
  case "$rest" in */*/*) ;; *) return 1 ;; esac
  first=${rest%%/*} rest=${rest#*/}
  second=${rest%%/*} rest=${rest#*/}
  [ -n "$first" ] && [ -n "$second" ] || return 1
  case "$rest" in T | T/*) return 0 ;; esac
  return 1
}

# Anything else (shared /tmp, a folder in HOME, a mounted volume) is refused so
# a strange TMPDIR can never turn user files into "temporary files".
temp_root_is_sane() {
  temp_root_has_shape "$1" || return 1
  has_newline "$1" && return 1
  path_is_under "$1" "$HOME_PHYS" && return 1
  path_is_under "$HOME_PHYS" "$1" && return 1
  [ -d "$1" ] && [ -O "$1" ]
}

# shellcheck disable=SC2034 # the state paths are read by state.sh
init_environment() {
  [ "$(uname -s 2>/dev/null)" = "Darwin" ] || fail UNSUPPORTED_PLATFORM
  [ "${EUID:-0}" -ne 0 ] || fail INTERNAL
  HOME_PHYS=$(physical_dir "${HOME:-}") || fail INTERNAL
  home_is_sane "$HOME_PHYS" || fail INTERNAL
  home_is_not_redirected || fail INTERNAL
  TEMP_ROOT=$(physical_dir "${TMPDIR:-}") || TEMP_ROOT=""
  if [ -n "$TEMP_ROOT" ] && ! temp_root_is_sane "$TEMP_ROOT"; then
    TEMP_ROOT=""
  fi
  LIBRARY="$HOME_PHYS/Library"
  STATE_DIR="$LIBRARY/Application Support/disk-cleanup"
  STATE_FILE="$STATE_DIR/state"
  LOG_DIR="$STATE_DIR/logs"
}

path_is_under() {
  [ "$1" = "$2" ] && return 0
  case "$1" in "$2"/*) return 0 ;; esac
  return 1
}

# True at, below, or above a guarded folder: removing an ancestor would take
# the guarded folder with it. Case-insensitive because the default macOS
# filesystem is.
relative_is_guarded() {
  local relative=$1 mode=$2 entry verdict=1
  shopt -s nocasematch
  for entry in "${NEVER_TOUCH[@]}"; do
    case "$relative" in "$entry" | "$entry"/*) verdict=0 ;; esac
    case "$entry" in "$relative"/*) verdict=0 ;; esac
  done
  for entry in "${PROTECTED_FOLDERS[@]}"; do
    case "$relative" in
      "$entry" | "$entry"/*)
        case "$mode:$relative" in
          tree:*/node_modules) ;;
          *) verdict=0 ;;
        esac
        ;;
    esac
  done
  shopt -u nocasematch
  return "$verdict"
}

location_is_allowed() {
  local mode=$1 physical=$2 relative
  case "$physical" in
    "$HOME_PHYS"/*)
      relative=${physical#"$HOME_PHYS"/}
      case "$relative" in
        */*) ;;
        "$TRASH_NAME") [ "$mode" = "contents" ] || return 1 ;;
        *) return 1 ;;
      esac
      ! relative_is_guarded "$relative" "$mode"
      return
      ;;
  esac
  [ -n "$TEMP_ROOT" ] || return 1
  case "$physical" in "$TEMP_ROOT"/*) return 0 ;; esac
  return 1
}

# Prints the physical path of a target that passes every guard.
guard_resolve() {
  local mode=$1 path=$2 parent name parent_physical
  case "$path" in /*) ;; *) return 1 ;; esac
  has_newline "$path" && return 1
  while [ "${path%/}" != "$path" ]; do path=${path%/}; done
  [ -n "$path" ] || return 1
  [ ! -L "$path" ] || return 1
  name=${path##*/}
  parent=${path%/*}
  case "$name" in "" | "." | "..") return 1 ;; esac
  case "$mode" in
    file) [ -f "$path" ] || return 1 ;;
    contents | old-files | empty-dir) [ -d "$path" ] || return 1 ;;
    tree) [ -d "$path" ] && [ "$name" = "$TREE_MODE_NAME" ] || return 1 ;;
    *) return 1 ;;
  esac
  parent_physical=$(physical_dir "${parent:-/}") || return 1
  location_is_allowed "$mode" "${parent_physical%/}/$name" || return 1
  printf '%s' "${parent_physical%/}/$name"
}

# guarded_delete MODE PATH [DAYS] is the only code that removes anything.
#   contents   everything inside directory PATH (PATH itself stays)
#   tree       directory PATH and everything inside it; node_modules only
#   empty-dir  directory PATH itself, only when nothing is inside it
#   file       the regular file PATH
#   old-files  regular files inside PATH not modified for more than DAYS days
guarded_delete() {
  local mode=${1:-} path=${2:-} days=${3:-} physical sink leftover
  local selector=()
  physical=$(guard_resolve "$mode" "$path") || return "$GUARD_REFUSED"
  case "$mode" in
    contents) selector=(-mindepth 1) ;;
    tree) selector=(-mindepth 0) ;;
    empty-dir) selector=(-maxdepth 0 -type d -empty) ;;
    file) selector=(-maxdepth 0 -type f) ;;
    old-files)
      is_uint "$days" && [ "$days" -ge 1 ] || return "$GUARD_REFUSED"
      selector=(-mindepth 1 -type f -mtime "+$days")
      ;;
  esac
  sink=${LOG_FILE:-/dev/null}
  find -P "$physical" -xdev "${selector[@]}" -delete -print >> "$sink" 2> /dev/null
  leftover=$(find -P "$physical" -xdev "${selector[@]}" -print -quit 2> /dev/null)
  [ -z "$leftover" ] || return "$GUARD_INCOMPLETE"
  [ "$mode" != "empty-dir" ] || [ ! -e "$physical" ] || return "$GUARD_INCOMPLETE"
}

can_list() {
  ls -A "$1" > /dev/null 2>&1
}

# measure_targets [DAYS]: allocated bytes and entry count of the TARGETS array;
# with DAYS only regular files older than that are counted. One find does the
# walk and the sizing (-ls prints "inode blocks mode ... path" from the data
# the walk already has), which is much faster than running stat on every file.
# A path with a line break would spill over several -ls lines, so those few
# entries go through stat instead, which prints the block count alone.
# shellcheck disable=SC2034 # MEASURE_* are read by scan.sh and clean.sh
measure_targets() {
  local days=${1:-} result
  local filter=(! -type d)
  local broken_path=$'*\n*'
  MEASURE_BYTES=0
  MEASURE_COUNT=0
  [ "${#TARGETS[@]}" -gt 0 ] || return 0
  [ -z "$days" ] || filter=(-type f -mtime "+$days")
  result=$(find -P "${TARGETS[@]}" -xdev "${filter[@]}" \
    \( -path "$broken_path" -exec stat -f '%b' {} + -o -ls \) 2> /dev/null |
    awk -v block="$BLOCK_BYTES" '
      NF == 1 && $1 ~ /^[0-9]+$/ { blocks += $1; count++; next }
      NF > 3 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ { blocks += $2; count++ }
      END { printf "%.0f %d", blocks * block, count }')
  is_uint "${result% *}" && is_uint "${result#* }" || return 0
  MEASURE_BYTES=${result% *}
  MEASURE_COUNT=${result#* }
}

# True when at least one non-directory entry exists below the TARGETS array.
targets_hold_files() {
  local found
  [ "${#TARGETS[@]}" -gt 0 ] || return 1
  found=$(find -P "${TARGETS[@]}" -xdev ! -type d -print -quit 2> /dev/null)
  [ -n "$found" ]
}

# Physical form of an absolute path whose tail may not exist yet: the deepest
# existing directory is resolved and the remaining names are appended.
physical_path() {
  local path=$1 tail="" resolved
  case "$path" in /*) ;; *) return 1 ;; esac
  has_newline "$path" && return 1
  while [ "${path%/}" != "$path" ]; do path=${path%/}; done
  while [ -n "$path" ] && [ ! -d "$path" ]; do
    [ ! -L "$path" ] || return 1
    tail="/${path##*/}$tail"
    path=${path%/*}
  done
  case "$tail/" in */./* | */../*) return 1 ;; esac
  resolved=$(physical_dir "${path:-/}") || return 1
  printf '%s%s' "${resolved%/}" "$tail"
}

disk_bytes() {
  df -kP "$HOME_PHYS" 2>/dev/null |
    awk 'NR == 2 { printf "%.0f %.0f", $2 * 1024, $4 * 1024 }'
}
