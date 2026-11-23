#!/usr/bin/env bats

load helpers/common

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

@test "no command is a usage error with exit code 2" {
  run_cleanup
  assert_error USAGE 2
}

@test "unknown command is a usage error" {
  run_cleanup purge
  assert_error USAGE 2
}

@test "unknown scan flag is a usage error" {
  run_cleanup scan --everything
  assert_error USAGE 2
}

@test "clean flags are rejected by scan" {
  run_cleanup scan --empty-trash
  assert_error USAGE 2
}

@test "flag without its value is a usage error" {
  run_cleanup scan --min-age-days
  assert_error USAGE 2
}

@test "clean without --categories is a usage error" {
  run_cleanup clean --token abcdef12
  assert_error USAGE 2
}

@test "there is no clean-everything mode" {
  scan_for_token
  clean_categories all
  assert_error UNKNOWN_CATEGORY
  clean_categories '*'
  assert_error UNKNOWN_CATEGORY
}

@test "non-numeric --min-age-days is an invalid argument" {
  run_cleanup scan --min-age-days soon
  assert_error INVALID_ARGUMENT
}

@test "--min-age-days below one day is rejected" {
  run_cleanup scan --min-age-days 0
  assert_error INVALID_ARGUMENT
}

@test "--min-idle-days below 30 is rejected" {
  scan_for_token --deep
  clean_categories node-modules-stale --min-idle-days 29
  assert_error INVALID_ARGUMENT
}

@test "--projects-dir must exist" {
  run_cleanup scan --deep --projects-dir "$SANDBOX_HOME/no-such-dir"
  assert_error INVALID_ARGUMENT
  assert_private no-such-dir
}

@test "--projects-dir outside the home directory is rejected" {
  run_cleanup scan --deep --projects-dir "$OUTSIDE"
  assert_error INVALID_ARGUMENT
}

@test "--projects-dir inside a dot-directory or Library is rejected" {
  mkdir -p "$SANDBOX_HOME/.hidden/work" "$SANDBOX_HOME/Library/work"
  run_cleanup scan --deep --projects-dir "$SANDBOX_HOME/.hidden/work"
  assert_error INVALID_ARGUMENT
  run_cleanup scan --deep --projects-dir "$SANDBOX_HOME/Library/work"
  assert_error INVALID_ARGUMENT
}

@test "--version prints a JSON document" {
  run_cleanup --version
  [ "$status" -eq 0 ]
  [ "$(json get command)" = "version" ]
  [[ "$(json get version)" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "--help prints a JSON document without touching the home directory" {
  run_cleanup --help
  [ "$status" -eq 0 ]
  [ "$(json get command)" = "help" ]
  assert_missing "$STATE_DIR"
}

@test "a non-macOS platform is refused" {
  stub_tool uname 'echo Linux'
  run_cleanup scan
  assert_error UNSUPPORTED_PLATFORM
  assert_missing "$STATE_DIR"
}

@test "the script finds its lib directory when invoked through a symlink" {
  mkdir -p "$SANDBOX/links/nested"
  ln -s "$CLEANUP" "$SANDBOX/links/first"
  ln -s ../first "$SANDBOX/links/nested/second"
  run sandbox_env /bin/bash "$SANDBOX/links/nested/second" --version
  [ "$status" -eq 0 ]
  [ "$(json get command)" = "version" ]
}

@test "a relative HOME is refused" {
  run env -i HOME="relative/home" TMPDIR="$SANDBOX_TMP" \
    PATH="$STUB_BIN:$TOOL_BIN:/bin" /bin/bash "$CLEANUP" scan
  assert_error INTERNAL
}

@test "a HOME that does not exist is refused" {
  run env -i HOME="$SANDBOX/absent-home" TMPDIR="$SANDBOX_TMP" \
    PATH="$STUB_BIN:$TOOL_BIN:/bin" /bin/bash "$CLEANUP" scan
  assert_error INTERNAL
  assert_private absent-home
}

@test "shallow home directories are never considered sane" {
  run sandbox_env /bin/bash -c 'source "$1"; home_is_sane /' _ "$CLEANUP"
  [ "$status" -ne 0 ]
  run sandbox_env /bin/bash -c 'source "$1"; home_is_sane /Users' _ "$CLEANUP"
  [ "$status" -ne 0 ]
  run sandbox_env /bin/bash -c 'source "$1"; home_is_sane "$HOME"' _ "$CLEANUP"
  [ "$status" -eq 0 ]
}

@test "an unexpected abort still prints one JSON error document" {
  run sandbox_env /bin/bash -c 'source "$1"; run_scan() { exit 7; }; main scan' _ "$CLEANUP"
  assert_error INTERNAL 7
  [ "${#lines[@]}" -eq 1 ]
}
