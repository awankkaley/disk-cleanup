#!/bin/bash
# Scan state (token, parameters, ok categories) and the optional clean log.

readonly STATE_FORMAT=1
readonly TOKEN_RANDOM_BYTES=4
readonly PRIVATE_DIR_MODE=700
readonly PRIVATE_FILE_MODE=600

ST_TOKEN=""
ST_EPOCH=""
ST_MIN_AGE=""
ST_DEEP=""
ST_PROJECTS_DIR=""
ST_OK=""

is_token() {
  case "${1:-}" in
    *[!0-9a-f]* | "") return 1 ;;
  esac
  [ "${#1}" -eq $((TOKEN_RANDOM_BYTES * 2)) ]
}

ensure_private_dir() {
  [ ! -L "$1" ] || return 1
  mkdir -p "$1" 2> /dev/null || return 1
  [ -d "$1" ] && [ -O "$1" ] && [ ! -L "$1" ] || return 1
  chmod "$PRIVATE_DIR_MODE" "$1" 2> /dev/null
}

new_token() {
  local token
  token=$(od -An -N"$TOKEN_RANDOM_BYTES" -tx1 /dev/urandom 2> /dev/null | tr -d ' \n')
  is_token "$token" || return 1
  printf '%s' "$token"
}

# state_write TOKEN OK_CATEGORIES
# shellcheck disable=SC2153 # OPT_* are the parsed options from cleanup.sh
state_write() {
  ensure_private_dir "$STATE_DIR" || return 1
  [ ! -L "$STATE_FILE" ] || return 1
  [ ! -e "$STATE_FILE" ] || [ -f "$STATE_FILE" ] || return 1
  (
    umask 077
    printf 'format=%s\ntoken=%s\nepoch=%s\nmin_age_days=%s\ndeep=%s\nprojects_dir=%s\nok_categories=%s\n' \
      "$STATE_FORMAT" "$1" "$(date +%s)" "$OPT_MIN_AGE" "$OPT_DEEP" "$OPT_PROJECTS_DIR" "$2" \
      > "$STATE_FILE"
  ) 2> /dev/null || return 1
  chmod "$PRIVATE_FILE_MODE" "$STATE_FILE" 2> /dev/null
}

state_assign() {
  case "$1" in
    token) ST_TOKEN=$2 ;;
    epoch) ST_EPOCH=$2 ;;
    min_age_days) ST_MIN_AGE=$2 ;;
    deep) ST_DEEP=$2 ;;
    projects_dir) ST_PROJECTS_DIR=$2 ;;
    ok_categories) ST_OK=$2 ;;
  esac
}

state_is_valid() {
  is_token "$ST_TOKEN" && is_uint "$ST_EPOCH" || return 1
  is_day_count "$ST_MIN_AGE" "$MIN_AGE_DAYS_FLOOR" || return 1
  case "$ST_DEEP" in 0 | 1) ;; *) return 1 ;; esac
  case "$ST_OK" in *[!a-z0-9,-]*) return 1 ;; esac
  [ -z "$ST_PROJECTS_DIR" ] || projects_dir_is_acceptable "$ST_PROJECTS_DIR"
}

# Loads ST_* from the state file; the content is validated, never executed.
state_read() {
  local line
  ST_TOKEN="" ST_EPOCH="" ST_MIN_AGE="" ST_DEEP="" ST_PROJECTS_DIR="" ST_OK=""
  [ -f "$STATE_FILE" ] && [ ! -L "$STATE_FILE" ] && [ -O "$STATE_FILE" ] || return 1
  [ ! -L "$STATE_DIR" ] || return 1
  while IFS= read -r line; do
    state_assign "${line%%=*}" "${line#*=}"
  done < "$STATE_FILE"
  state_is_valid
}

state_consume() {
  guarded_delete file "$STATE_FILE"
}

# Creates the log file for this clean run and points LOG_FILE at it.
log_open() {
  local file
  ensure_private_dir "$STATE_DIR" && ensure_private_dir "$LOG_DIR" || return 1
  file="$LOG_DIR/clean-$(date +%Y%m%d-%H%M%S)-$$.log"
  [ ! -e "$file" ] && [ ! -L "$file" ] || return 1
  (
    umask 077
    printf '# disk-cleanup %s: removed paths\n' "$(date '+%Y-%m-%d %H:%M:%S')" > "$file"
  ) 2> /dev/null || return 1
  chmod "$PRIVATE_FILE_MODE" "$file" 2> /dev/null || return 1
  LOG_FILE=$file
}

log_note() {
  [ -z "$LOG_FILE" ] || printf '# %s\n' "$1" >> "$LOG_FILE" 2> /dev/null
}
