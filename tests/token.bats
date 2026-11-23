#!/usr/bin/env bats

load helpers/common

setup() {
  setup_sandbox
  make_chrome_profile
  make_file "$SANDBOX_HOME/.Trash/discarded.bin" 8
}
teardown() { teardown_sandbox; }

set_state_field() {
  /usr/bin/sed -i '' "s/^$1=.*/$1=$2/" "$STATE_DIR/state"
}

@test "clean without a token reports TOKEN_MISSING" {
  scan_for_token
  run_cleanup clean --categories browser-chrome
  assert_error TOKEN_MISSING
  assert_exists "$CHROME_CACHE/Cache/Cache_Data/blob-one"
}

@test "clean before any scan reports TOKEN_INVALID" {
  run_cleanup clean --token abcdef12 --categories browser-chrome
  assert_error TOKEN_INVALID
  assert_exists "$CHROME_CACHE/Cache/Cache_Data/blob-one"
}

@test "a wrong token is rejected and nothing is deleted" {
  scan_for_token
  run_cleanup clean --token 00000000 --categories browser-chrome
  assert_error TOKEN_INVALID
  run_cleanup clean --token "not-a-token" --categories browser-chrome
  assert_error TOKEN_INVALID
  assert_exists "$CHROME_CACHE/Cache/Cache_Data/blob-one"
}

@test "a token older than 15 minutes is expired" {
  scan_for_token
  set_state_field epoch "$(($(date +%s) - 901))"
  clean_categories browser-chrome
  assert_error TOKEN_EXPIRED
  assert_exists "$CHROME_CACHE/Cache/Cache_Data/blob-one"
}

@test "a token just inside the 15 minute window still works" {
  scan_for_token
  set_state_field epoch "$(($(date +%s) - 800))"
  clean_categories browser-chrome
  [ "$status" -eq 0 ]
  [ "$(json res browser-chrome status)" = "cleaned" ]
}

@test "a state file dated in the future is invalid" {
  scan_for_token
  set_state_field epoch "$(($(date +%s) + 5000))"
  clean_categories browser-chrome
  assert_error TOKEN_INVALID
}

@test "the token is single-use" {
  scan_for_token
  clean_categories browser-chrome
  [ "$status" -eq 0 ]
  assert_missing "$STATE_DIR/state"
  make_file "$CHROME_CACHE/Cache/Cache_Data/blob-new" 8
  clean_categories browser-chrome
  assert_error TOKEN_INVALID
  assert_exists "$CHROME_CACHE/Cache/Cache_Data/blob-new"
}

@test "a category that was not ok in the scan cannot be cleaned" {
  scan_for_token
  [ "$(json cat browser-firefox status)" = "not_found" ]
  clean_categories browser-chrome,browser-firefox
  assert_error CATEGORY_NOT_IN_SCAN
  assert_exists "$CHROME_CACHE/Cache/Cache_Data/blob-one"
}

@test "a rejected request keeps the token usable" {
  scan_for_token
  clean_categories browser-firefox
  assert_error CATEGORY_NOT_IN_SCAN
  clean_categories browser-chrome
  [ "$status" -eq 0 ]
}

@test "an unknown category id is rejected without echoing it" {
  scan_for_token
  clean_categories "browser-chrome,../../Documents"
  assert_error UNKNOWN_CATEGORY
  assert_private Documents
  assert_exists "$CHROME_CACHE/Cache/Cache_Data/blob-one"
}

@test "trash requires --empty-trash" {
  scan_for_token
  [ "$(json cat trash status)" = "ok" ]
  clean_categories trash
  assert_error TRASH_FLAG_REQUIRED
  assert_exists "$SANDBOX_HOME/.Trash/discarded.bin"
}

@test "node-modules-stale requires a deep scan token" {
  make_project "$SANDBOX_HOME/code/idle-app" 100
  scan_for_token
  clean_categories node-modules-stale
  assert_error DEEP_SCAN_REQUIRED
  assert_exists "$SANDBOX_HOME/code/idle-app/node_modules/left-pad/index.js"
}

@test "a tampered state file is invalid" {
  scan_for_token
  set_state_field epoch "tomorrow"
  clean_categories browser-chrome
  assert_error TOKEN_INVALID
}

@test "categories injected into the state file are still re-validated by flags" {
  scan_for_token
  set_state_field ok_categories "browser-chrome,trash,node-modules-stale"
  clean_categories trash
  assert_error TRASH_FLAG_REQUIRED
  clean_categories node-modules-stale
  assert_error DEEP_SCAN_REQUIRED
}

@test "a symlinked state file is not trusted" {
  scan_for_token
  mv "$STATE_DIR/state" "$OUTSIDE/state-copy"
  ln -s "$OUTSIDE/state-copy" "$STATE_DIR/state"
  clean_categories browser-chrome
  assert_error TOKEN_INVALID
  assert_exists "$OUTSIDE/state-copy"
}

@test "a new scan invalidates the previous token" {
  scan_for_token
  local first=$TOKEN
  scan_for_token
  [ "$first" != "$TOKEN" ]
  run_cleanup clean --token "$first" --categories browser-chrome
  assert_error TOKEN_INVALID
}
