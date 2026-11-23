#!/bin/bash
# JSON output. Every string is a static constant or a validated identifier;
# numbers are validated integers. Nothing read from disk is ever printed.

readonly MAX_UINT_DIGITS=18

DOCUMENT_EMITTED=0

is_uint() {
  case "${1:-}" in
    "" | *[!0-9]*) return 1 ;;
  esac
  [ "${#1}" -le "$MAX_UINT_DIGITS" ]
}

error_message() {
  case "$1" in
    USAGE) printf 'Usage: cleanup scan [--deep] [--min-age-days N] [--projects-dir PATH] or cleanup clean --token ID --categories id1,id2 [--empty-trash] [--min-idle-days N] [--log].' ;;
    UNKNOWN_CATEGORY) printf 'At least one requested category id does not exist on this platform.' ;;
    TOKEN_MISSING) printf 'Run scan first and pass its token with --token.' ;;
    TOKEN_INVALID) printf 'The token does not match the latest scan. Run scan again.' ;;
    TOKEN_EXPIRED) printf 'Run scan again; the previous scan is older than 15 minutes.' ;;
    CATEGORY_NOT_IN_SCAN) printf 'Every requested category must have status ok in the scan that issued the token.' ;;
    TRASH_FLAG_REQUIRED) printf 'Emptying the trash is irreversible and requires --empty-trash.' ;;
    DEEP_SCAN_REQUIRED) printf 'node-modules-stale requires a token from scan --deep.' ;;
    INVALID_ARGUMENT) printf 'An option value is not acceptable. Day counts must be whole numbers within the allowed range and the projects directory must be an existing folder inside the home directory.' ;;
    UNSUPPORTED_PLATFORM) printf 'This script supports macOS only.' ;;
    *) printf 'The script could not run safely in this environment.' ;;
  esac
}

# Must be called from the main shell, never from a command substitution.
fail() {
  local code=$1 exit_code=$EXIT_ERROR
  case "$code" in
    USAGE) exit_code=$EXIT_USAGE ;;
    UNKNOWN_CATEGORY | TOKEN_MISSING | TOKEN_INVALID | TOKEN_EXPIRED | CATEGORY_NOT_IN_SCAN) ;;
    TRASH_FLAG_REQUIRED | DEEP_SCAN_REQUIRED | INVALID_ARGUMENT | UNSUPPORTED_PLATFORM) ;;
    *) code=INTERNAL ;;
  esac
  emit_document "$(printf '{"schema_version":%d,"error":{"code":"%s","message":"%s"}}' \
    "$SCHEMA_VERSION" "$code" "$(error_message "$code")")"
  exit "$exit_code"
}

# Every run prints exactly one document through here.
emit_document() {
  DOCUMENT_EMITTED=1
  printf '%s\n' "$1"
}

# EXIT trap: an unexpected abort still yields a JSON error, never silence.
emit_error_if_silent() {
  [ "$DOCUMENT_EMITTED" = 1 ] || emit_document "$(printf \
    '{"schema_version":%d,"error":{"code":"INTERNAL","message":"%s"}}' \
    "$SCHEMA_VERSION" "$(error_message INTERNAL)")"
}

emit_version() {
  emit_document "$(printf '{"schema_version":%d,"command":"version","version":"%s"}' \
    "$SCHEMA_VERSION" "$VERSION")"
}

emit_help() {
  emit_document "$(printf '{"schema_version":%d,"command":"help","usage":"%s"}' \
    "$SCHEMA_VERSION" "$(error_message USAGE)")"
}

json_bool() {
  if [ "$1" = 1 ]; then printf 'true'; else printf 'false'; fi
}

json_uint_or_null() {
  if is_uint "${1:-}"; then printf '%s' "$1"; else printf 'null'; fi
}

# Uses CAT_* of the looked-up category plus the R_* scan result.
json_scan_category() {
  local recommended=0 flag='null'
  [ "$CAT_RISK" = "safe" ] && recommended=1
  [ "$CAT_ID" = "$TRASH_CATEGORY" ] && flag="\"$TRASH_FLAG\""
  printf '{"id":"%s","label":"%s","group":"%s","size_bytes":%s,"item_count":%s,' \
    "$CAT_ID" "$CAT_LABEL" "$CAT_GROUP" "$(json_uint_or_null "$R_SIZE")" "$(json_uint_or_null "$R_COUNT")"
  printf '"status":"%s","recommended":%s,"risk":"%s","impact":"%s","requires_flag":%s%s}' \
    "$R_STATUS" "$(json_bool "$recommended")" "$CAT_RISK" "$CAT_IMPACT" "$flag" "$R_EXTRA"
}

json_clean_result() {
  local error='null'
  [ -z "$R_ERROR" ] || error="\"$R_ERROR\""
  printf '{"id":"%s","label":"%s","freed_bytes":%s,"status":"%s","error_code":%s}' \
    "$CAT_ID" "$CAT_LABEL" "$R_FREED" "$R_STATUS" "$error"
}
