#!/usr/bin/env bats

load helpers/common

bats_require_minimum_version 1.5.0

FIXTURE_NAMES=(zebra-profile quokka-app.bin wombat-project okapi-cache narwhal.log)

setup() {
  setup_sandbox
  make_file "$SANDBOX_HOME/Library/Caches/Google/Chrome/zebra-profile/Cache/quokka-app.bin" 8
  make_file "$SANDBOX_HOME/Library/Caches/okapi-cache/quokka-app.bin" 8
  make_file "$SANDBOX_HOME/.Trash/quokka-app.bin" 8
  make_file "$SANDBOX_HOME/Library/Logs/narwhal.log" 8
  age_path "$SANDBOX_HOME/Library/Logs/narwhal.log" 30
  make_file "$SANDBOX_TMP/okapi-cache/quokka-app.bin" 8
  age_path "$SANDBOX_TMP/okapi-cache/quokka-app.bin" 30
  make_project "$SANDBOX_HOME/work/wombat-project" 200
}
teardown() { teardown_sandbox; }

@test "scan output carries no names or paths" {
  run_cleanup scan --deep
  [ "$status" -eq 0 ]
  assert_json_schema scan
  assert_private "${FIXTURE_NAMES[@]}"
}

@test "clean output carries no names or paths" {
  scan_for_token --deep
  clean_categories "$(json ok-ids)" --empty-trash
  [ "$status" -eq 0 ]
  assert_json_schema clean
  assert_private "${FIXTURE_NAMES[@]}"
  assert_missing "$SANDBOX_HOME/work/wombat-project/node_modules"
}

@test "clean output with --log exposes only the fixed location hint" {
  scan_for_token --deep
  clean_categories "$(json ok-ids)" --empty-trash --log
  [ "$status" -eq 0 ]
  assert_private "${FIXTURE_NAMES[@]}"
  [ "${#lines[@]}" -eq 1 ]
}

@test "error output never echoes user input" {
  run_cleanup scan --deep --projects-dir "$SANDBOX_HOME/work/wombat-project/ghost-dir"
  assert_error INVALID_ARGUMENT
  assert_private "${FIXTURE_NAMES[@]}" ghost-dir
  run_cleanup "wombat-project/command"
  assert_error USAGE 2
  assert_private "${FIXTURE_NAMES[@]}"
  run_cleanup scan --min-age-days "narwhal.log"
  assert_error INVALID_ARGUMENT
  assert_private "${FIXTURE_NAMES[@]}"
  run_cleanup clean --token "zebra-profile" --categories "okapi-cache"
  assert_private "${FIXTURE_NAMES[@]}"
}

@test "failures of external tools never leak their output" {
  stub_tool docker 'echo "error at /Users/zebra-profile/socket" >&2; echo "zebra-profile"; exit 1'
  stub_tool npm 'echo "npm ERR! path /Users/zebra-profile" >&2; echo zebra-profile; exit 1'
  make_file "$SANDBOX_HOME/.npm/_cacache/quokka-app.bin" 8
  scan_for_token
  assert_private "${FIXTURE_NAMES[@]}"
  clean_categories npm-cache
  [ "$status" -eq 0 ]
  assert_private "${FIXTURE_NAMES[@]}"
  [ "${#lines[@]}" -eq 1 ]
}

@test "unreadable folders produce no error text" {
  chmod 000 "$SANDBOX_HOME/Library/Caches/okapi-cache"
  run_cleanup scan
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  assert_private "${FIXTURE_NAMES[@]}"
}

@test "nothing is written to stderr" {
  run --separate-stderr sandbox_env /bin/bash "$CLEANUP" scan --deep
  [ -z "$stderr" ]
  run --separate-stderr sandbox_env /bin/bash "$CLEANUP" clean --categories nonsense
  [ -z "$stderr" ]
}

@test "labels and impacts are identical across runs with different data" {
  run_cleanup scan
  local first
  first=$(printf '%s' "$output" | /usr/bin/perl -MJSON::PP -e \
    'local $/; my $d = decode_json(<STDIN>); print join("|", map { "$_->{label}:$_->{impact}" } @{$d->{categories}})')
  teardown_sandbox
  setup_sandbox
  run_cleanup scan
  local second
  second=$(printf '%s' "$output" | /usr/bin/perl -MJSON::PP -e \
    'local $/; my $d = decode_json(<STDIN>); print join("|", map { "$_->{label}:$_->{impact}" } @{$d->{categories}})')
  [ "$first" = "$second" ]
}
