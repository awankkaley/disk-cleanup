#!/usr/bin/env bats

load helpers/common

setup() {
  setup_sandbox
  DOWNLOADS="$SANDBOX_HOME/Downloads"
  mkdir -p "$DOWNLOADS"
}
teardown() { teardown_sandbox; }

SCRIPTS=("$PROJECT_ROOT/scripts/cleanup.sh" "$PROJECT_ROOT"/scripts/lib/*.sh)

code_lines() {
  /usr/bin/grep -hvE '^[[:space:]]*#' "${SCRIPTS[@]}"
}

guard() { run_function guarded_delete "$@"; }

@test "static: exactly one place moves files and it lives in the trash routine" {
  [ "$(code_lines | /usr/bin/grep -cE '(^|[^[:alnum:]_-])mv[[:space:]]')" -eq 1 ]
  [ "$(/usr/bin/grep -cE '(^|[^[:alnum:]_-])mv[[:space:]]' "$PROJECT_ROOT/scripts/lib/trash.sh")" -eq 1 ]
  run /usr/bin/grep -lE '(^|[^[:alnum:]_-])(cp|ditto|rsync|ln|dd)[[:space:]]' "${SCRIPTS[@]}"
  [ -z "$output" ]
}

@test "static: the trash routine has exactly one call site" {
  [ "$(code_lines | /usr/bin/grep -cE '(^|[^[:alnum:]_])trash_file([^[:alnum:]_]|$)')" -eq 2 ]
  [ "$(code_lines | /usr/bin/grep -cE '^trash_file\(\)')" -eq 1 ]
  [ "$(code_lines | /usr/bin/grep -cE '[[:space:]]osascript[[:space:]]')" -eq 1 ]
}

@test "static: permanent deletion still has exactly one call site" {
  local offenders
  offenders=$(/usr/bin/grep -nE '(^|[^[:alnum:]_-])(rm|rmdir|unlink)[[:space:]]|-delete|-exec[[:space:]]+rm' \
    "${SCRIPTS[@]}" | /usr/bin/grep -v '^[^:]*guard\.sh:' || true)
  [ -z "$offenders" ]
  [ "$(/usr/bin/grep -c -- '-delete' "$PROJECT_ROOT/scripts/lib/guard.sh")" -eq 1 ]
  run /usr/bin/grep -nE 'guarded_delete' "$PROJECT_ROOT/scripts/lib/trash.sh"
  [ -z "$output" ]
}

@test "static: file paths are never interpolated into AppleScript source" {
  run /usr/bin/grep -nE "osascript.*-e[[:space:]]+\"[^\"]*\\$" "${SCRIPTS[@]}"
  [ -z "$output" ]
  run /usr/bin/grep -nE '(^|[^[:alnum:]_])(eval|source[[:space:]]+"\$[^S])' "${SCRIPTS[@]}"
  [ -z "$output" ]
}

SELECTION_SECRET="0123456789abcdef0123456789abcdef"
SELECTION_BODY='{"token":"abcdef12","secret":"0123456789abcdef0123456789abcdef","ids":[1]}'

@test "guard: the selection exception removes only a selection file with the right token and secret" {
  printf '%s' "$SELECTION_BODY" > "$DOWNLOADS/disk-cleanup-selection.json"
  guard selection "$DOWNLOADS/disk-cleanup-selection.json" 12345678 "$SELECTION_SECRET"
  [ "$status" -ne 0 ]
  assert_exists "$DOWNLOADS/disk-cleanup-selection.json"
  guard selection "$DOWNLOADS/disk-cleanup-selection.json"
  [ "$status" -ne 0 ]
  assert_exists "$DOWNLOADS/disk-cleanup-selection.json"
  guard selection "$DOWNLOADS/disk-cleanup-selection.json" abcdef12
  [ "$status" -ne 0 ]
  assert_exists "$DOWNLOADS/disk-cleanup-selection.json"
  guard selection "$DOWNLOADS/disk-cleanup-selection.json" abcdef12 "ffffffffffffffffffffffffffffffff"
  [ "$status" -ne 0 ]
  assert_exists "$DOWNLOADS/disk-cleanup-selection.json"
  guard selection "$DOWNLOADS/disk-cleanup-selection.json" abcdef12 "$SELECTION_SECRET"
  [ "$status" -eq 0 ]
  assert_missing "$DOWNLOADS/disk-cleanup-selection.json"
}

@test "guard: a selection file without the secret is never removed" {
  printf '{"token":"abcdef12","ids":[1]}' > "$DOWNLOADS/disk-cleanup-selection.json"
  guard selection "$DOWNLOADS/disk-cleanup-selection.json" abcdef12 "$SELECTION_SECRET"
  [ "$status" -ne 0 ]
  assert_exists "$DOWNLOADS/disk-cleanup-selection.json"
}

@test "guard: the selection exception refuses every other file in Downloads" {
  printf '%s' "$SELECTION_BODY" > "$DOWNLOADS/tax-return.json"
  printf '%s' "$SELECTION_BODY" > "$DOWNLOADS/disk-cleanup-selection-old.json"
  printf 'my notes' > "$DOWNLOADS/disk-cleanup-selection (1).json"
  guard selection "$DOWNLOADS/tax-return.json" abcdef12 "$SELECTION_SECRET"
  [ "$status" -ne 0 ]
  guard selection "$DOWNLOADS/disk-cleanup-selection-old.json" abcdef12 "$SELECTION_SECRET"
  [ "$status" -ne 0 ]
  guard selection "$DOWNLOADS/disk-cleanup-selection (1).json" abcdef12 "$SELECTION_SECRET"
  [ "$status" -ne 0 ]
  guard file "$DOWNLOADS/tax-return.json"
  [ "$status" -ne 0 ]
  guard contents "$DOWNLOADS"
  [ "$status" -ne 0 ]
  assert_exists "$DOWNLOADS/tax-return.json"
  assert_exists "$DOWNLOADS/disk-cleanup-selection-old.json"
  assert_exists "$DOWNLOADS/disk-cleanup-selection (1).json"
}

@test "guard: the selection exception applies in Downloads only and never to links or folders" {
  mkdir -p "$SANDBOX_HOME/Documents" "$DOWNLOADS/sub" "$DOWNLOADS/disk-cleanup-selection-2.json"
  printf '%s' "$SELECTION_BODY" > "$SANDBOX_HOME/Documents/disk-cleanup-selection.json"
  printf '%s' "$SELECTION_BODY" > "$DOWNLOADS/sub/disk-cleanup-selection.json"
  printf '%s' "$SELECTION_BODY" > "$OUTSIDE/disk-cleanup-selection.json"
  ln -s "$OUTSIDE/disk-cleanup-selection.json" "$DOWNLOADS/disk-cleanup-selection.json"
  local target
  for target in "$SANDBOX_HOME/Documents/disk-cleanup-selection.json" "$DOWNLOADS/sub/disk-cleanup-selection.json" \
    "$OUTSIDE/disk-cleanup-selection.json" "$DOWNLOADS/disk-cleanup-selection.json" \
    "$DOWNLOADS/disk-cleanup-selection-2.json"; do
    guard selection "$target" abcdef12 "$SELECTION_SECRET"
    [ "$status" -ne 0 ]
    assert_exists "$target"
  done
}

@test "trash routine: refuses a file that does not match the recorded facts" {
  make_file "$SANDBOX_HOME/Documents/report.doc" 8
  local mtime
  mtime=$(/usr/bin/stat -f '%m' "$SANDBOX_HOME/Documents/report.doc")
  run_function trash_file "$SANDBOX_HOME/Documents" "report.doc" 4096 8192 "$mtime"
  [ "$status" -eq 3 ]
  run_function trash_file "$SANDBOX_HOME/Documents" "report.doc" 8192 8192 "$((mtime - 1))"
  [ "$status" -eq 3 ]
  run_function trash_file "$SANDBOX_HOME/Documents/" "report.doc" 8192 8192 "$mtime"
  [ "$status" -eq 3 ]
  run_function trash_file "$SANDBOX_HOME" "Documents" 0 64 "$mtime"
  [ "$status" -eq 3 ]
  assert_exists "$SANDBOX_HOME/Documents/report.doc"
  run_function trash_file "$SANDBOX_HOME/Documents" "report.doc" 8192 8192 "$mtime"
  [ "$status" -eq 6 ]
  assert_missing "$SANDBOX_HOME/Documents/report.doc"
  trash_holds "report.doc"
}

@test "trash routine: a name cut for a suffix never ends inside a character" {
  run_function utf8_prefix "aé" 2
  [ "$output" = "a" ]
  run_function utf8_prefix "aé" 3
  [ "$output" = "aé" ]
  run_function utf8_prefix "😀😀" 6
  [ "$output" = "😀" ]
  run_function utf8_prefix "plain" 3
  [ "$output" = "pla" ]
}
