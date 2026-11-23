#!/usr/bin/env bats

load helpers/common

bats_require_minimum_version 1.5.0

# The report and the manifest list personal file names, so they must not
# outlive the review: every command start discards an expired review.

setup() {
  setup_sandbox
  HOME_DIR=$SANDBOX_HOME
  VIDEO="$HOME_DIR/Movies/heron-video.mov"
  make_big_file "$VIDEO" 12
  make_chrome_profile
  stub_open
  review_for_token
}
teardown() { teardown_sandbox; }

expire_review() {
  /usr/bin/sed -i '' "s/^epoch=.*/epoch=$(($(date +%s) - ${1:-3601}))/" "$MANIFEST"
}

assert_review_discarded() {
  assert_missing "$MANIFEST" && assert_missing "$REPORT"
}

assert_review_kept() {
  assert_exists "$MANIFEST" && assert_exists "$REPORT"
}

@test "scan discards an expired review and keeps a live one" {
  run_cleanup scan
  [ "$status" -eq 0 ]
  assert_review_kept
  expire_review
  run_cleanup scan
  [ "$status" -eq 0 ]
  assert_json_schema scan
  assert_review_discarded
  assert_exists "$VIDEO"
}

@test "clean discards an expired review, even when the request is rejected" {
  scan_for_token
  expire_review
  clean_categories browser-chrome
  [ "$status" -eq 0 ]
  assert_review_discarded
  review_for_token
  expire_review
  run_cleanup clean --token 00000000 --categories browser-chrome
  assert_error TOKEN_INVALID
  assert_review_discarded
  assert_exists "$VIDEO"
}

@test "help and version discard an expired review and keep a live one" {
  run_cleanup --help
  [ "$status" -eq 0 ]
  assert_review_kept
  expire_review
  run_cleanup --help
  [ "$status" -eq 0 ]
  [ "$(json get command)" = "help" ]
  assert_review_discarded
  review_for_token
  run_cleanup --version
  assert_review_kept
  expire_review
  run_cleanup --version
  [ "$status" -eq 0 ]
  [ "$(json get command)" = "version" ]
  assert_review_discarded
}

@test "help in an unusable environment still answers and removes nothing" {
  expire_review
  stub_tool uname 'echo Linux'
  run_cleanup --help
  [ "$status" -eq 0 ]
  [ "$(json get command)" = "help" ]
  assert_review_kept
}

@test "a new review replaces an expired one" {
  local first=$TOKEN
  expire_review
  review_for_token
  [ "$first" != "$TOKEN" ]
  assert_review_kept
  [ "$(/usr/bin/grep -c '^token=' "$MANIFEST")" = "1" ]
}

@test "review-apply discards an expired review whatever token it is given" {
  expire_review
  write_selection "$TOKEN" 1
  apply_review 00000000
  assert_error TOKEN_INVALID
  assert_review_discarded
  review_for_token
  expire_review
  run_cleanup review-apply
  assert_error TOKEN_MISSING
  assert_review_discarded
  review_for_token
  expire_review
  apply_review
  assert_error TOKEN_EXPIRED
  assert_review_discarded
  assert_exists "$VIDEO"
}

@test "a damaged or future-dated review is discarded as well" {
  /usr/bin/sed -i '' 's/^epoch=.*/epoch=soon/' "$MANIFEST"
  run_cleanup scan
  assert_review_discarded
  review_for_token
  expire_review -5000
  run_cleanup scan
  assert_review_discarded
  review_for_token
  /bin/rm "$MANIFEST"
  run_cleanup scan
  assert_missing "$REPORT"
}

@test "the sweep never follows a planted link and touches nothing else" {
  echo keep > "$OUTSIDE/victim-file"
  /bin/rm "$MANIFEST" "$REPORT"
  ln -s "$OUTSIDE/victim-file" "$MANIFEST"
  ln -s "$OUTSIDE/victim-file" "$REPORT"
  make_file "$STATE_DIR/logs/clean-old.log" 4
  run_cleanup scan
  [ "$status" -eq 0 ]
  [ "$(/bin/cat "$OUTSIDE/victim-file")" = "keep" ]
  assert_exists "$STATE_DIR/logs/clean-old.log"
  assert_exists "$STATE_DIR/state"
}

@test "the sweep prints nothing of its own" {
  expire_review
  run --separate-stderr sandbox_env /bin/bash "$CLEANUP" scan
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "${#lines[@]}" -eq 1 ]
  assert_private heron-video
}
