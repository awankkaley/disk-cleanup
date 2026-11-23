#!/bin/bash
# The single routine that moves a personal file to the Trash. Nothing here
# deletes: a file either ends up in the Trash or stays exactly where it is.

readonly TRASH_DONE=0
readonly TRASH_CHANGED=3
readonly TRASH_DENIED=4
readonly TRASH_FAILED=5
# Moved, but without Finder: the caller stops asking Finder for later items.
readonly TRASH_DONE_DIRECT=6
readonly FINDER_SECONDS=30
readonly FINDER_LOCALE="en_US.UTF-8"
# The path is handed over as an argument (argv) and is never part of the
# AppleScript source, so no file name can alter the script.
readonly FINDER_SCRIPT=(
  -e 'on run argv'
  -e 'set theItem to POSIX file (item 1 of argv)'
  -e 'tell application "Finder" to delete theItem'
  -e 'end run'
)
readonly REGULAR_FILE_TYPE="Regular File"
readonly TRASH_MAX_COPIES=999
readonly TRASH_STEM_BYTES=180
readonly TRASH_EXTENSION_BYTES=16

HOME_DEVICE=""
FINDER_ENABLED=1

home_device() {
  [ -n "$HOME_DEVICE" ] || HOME_DEVICE=$(stat -f '%d' "$HOME_PHYS" 2> /dev/null)
  printf '%s' "$HOME_DEVICE"
}

# True while ./NAME is still the regular file the review recorded: same
# allocation, size and modification time, on the home volume, not a link.
trash_item_unchanged() {
  local name=$1 facts expected
  [ ! -L "./$name" ] && [ -f "./$name" ] || return 1
  expected="$REGULAR_FILE_TYPE|$((10#$2 / BLOCK_BYTES))|$3|$4|$(home_device)"
  facts=$(stat -f '%HT|%b|%z|%m|%d' "./$name" 2> /dev/null) || return 1
  [ "$facts" = "$expected" ]
}

item_is_gone() {
  [ ! -e "./$1" ] && [ ! -L "./$1" ]
}

# Finder keeps the original location, so the user gets "Put Back".
finder_trash() {
  [ "$FINDER_ENABLED" = 1 ] || return 1
  (
    export LC_ALL=$FINDER_LOCALE
    run_tool "$FINDER_SECONDS" osascript "${FINDER_SCRIPT[@]}" "$1" > /dev/null
  )
}

# Longest prefix of STRING within LIMIT bytes that ends on a character
# boundary (LC_ALL=C makes every index a byte).
utf8_prefix() {
  local text=$1 limit=$2 prefix
  prefix=${text:0:limit}
  case "${text:limit:1}" in
    [$'\x80'-$'\xbf'])
      while case "$prefix" in *[$'\x80'-$'\xbf']) true ;; *) false ;; esac; do
        prefix=${prefix%?}
      done
      prefix=${prefix%?}
      ;;
  esac
  printf '%s' "$prefix"
}

trash_dir_is_usable() {
  local trash=$1
  [ ! -L "$trash" ] || return 1
  [ -d "$trash" ] || mkdir -m "$PRIVATE_DIR_MODE" "$trash" 2> /dev/null || return 1
  is_real_dir "$trash" && [ -O "$trash" ] || return 1
  [ "$(stat -f '%d' "$trash" 2> /dev/null)" = "$(home_device)" ]
}

# Prints a path inside the Trash that nothing occupies: the original name,
# or "name 2.ext", "name 3.ext", ...
trash_destination() {
  local name=$1 trash="$HOME_PHYS/$TRASH_NAME" stem extension="" candidate copy=1
  trash_dir_is_usable "$trash" || return 1
  stem=$name
  case "$name" in
    ?*.*)
      extension=".${name##*.}"
      if [ "${#extension}" -le "$TRASH_EXTENSION_BYTES" ]; then stem=${name%.*}; else extension=""; fi
      ;;
  esac
  candidate="$trash/$name"
  while [ -e "$candidate" ] || [ -L "$candidate" ]; do
    copy=$((copy + 1))
    [ "$copy" -le "$TRASH_MAX_COPIES" ] || return 1
    candidate="$trash/$(utf8_prefix "$stem" "$TRASH_STEM_BYTES") $copy$extension"
  done
  printf '%s' "$candidate"
}

# Without Finder: a rename into ~/.Trash on the same volume. -n never
# overwrites, and the result is checked instead of trusting the exit status.
move_into_trash() {
  local name=$1 destination
  destination=$(trash_destination "$name") || return 1
  mv -n -- "./$name" "$destination" 2> /dev/null
  item_is_gone "$name" && [ -e "$destination" ]
}

trash_failure_code() {
  local trash="$HOME_PHYS/$TRASH_NAME"
  if [ -w . ] && is_real_dir "$trash" && [ -w "$trash" ] && can_list "$trash"; then
    return "$TRASH_FAILED"
  fi
  return "$TRASH_DENIED"
}

# trash_file PARENT NAME ALLOCATED SIZE MTIME: the only code that moves a
# personal file. It runs in a subshell pinned to the recorded parent folder,
# so a parent swapped for a link afterwards cannot redirect the move, and it
# checks the file again right before each attempt.
trash_file() (
  parent=$1 name=$2
  if ! cd -P -- "$parent" 2> /dev/null; then
    is_real_dir "$parent" && exit "$TRASH_DENIED"
    exit "$TRASH_CHANGED"
  fi
  [ "$(pwd -P)" = "$parent" ] || exit "$TRASH_CHANGED"
  trash_item_unchanged "$name" "$3" "$4" "$5" || exit "$TRASH_CHANGED"
  finder_trash "$parent/$name"
  item_is_gone "$name" && exit "$TRASH_DONE"
  trash_item_unchanged "$name" "$3" "$4" "$5" || exit "$TRASH_CHANGED"
  move_into_trash "$name" && exit "$TRASH_DONE_DIRECT"
  trash_failure_code
)
