#!/usr/bin/env bats

load helpers/common

setup() {
  setup_sandbox
  LOGS="$SANDBOX_HOME/Library/Logs"
}
teardown() { teardown_sandbox; }

aged_file() {
  make_file "$1" 8
  age_path "$1" "$2"
}

@test "temp-files counts only files older than the default 7 days" {
  aged_file "$SANDBOX_TMP/ancient.bin" 30
  aged_file "$SANDBOX_TMP/nested/older.bin" 8
  aged_file "$SANDBOX_TMP/recent.bin" 6
  make_file "$SANDBOX_TMP/fresh.bin" 8
  run_cleanup scan
  [ "$(json cat temp-files status)" = "ok" ]
  [ "$(json cat temp-files item_count)" = "2" ]
}

@test "temp-files with nothing old enough is empty" {
  aged_file "$SANDBOX_TMP/recent.bin" 3
  run_cleanup scan
  [ "$(json cat temp-files status)" = "empty" ]
}

@test "cleaning temp-files removes old files and keeps recent ones" {
  aged_file "$SANDBOX_TMP/ancient.bin" 30
  aged_file "$SANDBOX_TMP/nested/deep/older.bin" 8
  aged_file "$SANDBOX_TMP/nested/recent.bin" 6
  aged_file "$SANDBOX_TMP/recent.bin" 2
  scan_for_token
  clean_categories temp-files
  [ "$(json res temp-files status)" = "cleaned" ]
  [ "$(json res temp-files freed_bytes)" -ge 16384 ]
  assert_missing "$SANDBOX_TMP/ancient.bin"
  assert_missing "$SANDBOX_TMP/nested/deep/older.bin"
  assert_exists "$SANDBOX_TMP/nested/recent.bin"
  assert_exists "$SANDBOX_TMP/recent.bin"
  [ -d "$SANDBOX_TMP/nested/deep" ]
}

@test "--min-age-days changes the threshold and clean reuses it" {
  aged_file "$SANDBOX_TMP/ancient.bin" 45
  aged_file "$SANDBOX_TMP/middle.bin" 15
  aged_file "$LOGS/ancient.log" 45
  aged_file "$LOGS/middle.log" 15
  scan_for_token --min-age-days 30
  [ "$(json cat temp-files item_count)" = "1" ]
  [ "$(json cat logs item_count)" = "1" ]
  clean_categories temp-files,logs
  [ "$status" -eq 0 ]
  assert_missing "$SANDBOX_TMP/ancient.bin"
  assert_missing "$LOGS/ancient.log"
  assert_exists "$SANDBOX_TMP/middle.bin"
  assert_exists "$LOGS/middle.log"
}

@test "clean does not accept its own age threshold" {
  aged_file "$SANDBOX_TMP/ancient.bin" 45
  scan_for_token
  clean_categories temp-files --min-age-days 1
  assert_error USAGE 2
  assert_exists "$SANDBOX_TMP/ancient.bin"
}

@test "logs include diagnostic reports and respect the threshold" {
  aged_file "$LOGS/app/old.log" 20
  aged_file "$LOGS/DiagnosticReports/old.crash" 20
  aged_file "$LOGS/DiagnosticReports/recent.crash" 1
  scan_for_token
  [ "$(json cat logs status)" = "ok" ]
  [ "$(json cat logs item_count)" = "2" ]
  clean_categories logs
  [ "$(json res logs status)" = "cleaned" ]
  assert_missing "$LOGS/app/old.log"
  assert_missing "$LOGS/DiagnosticReports/old.crash"
  assert_exists "$LOGS/DiagnosticReports/recent.crash"
  [ -d "$LOGS/DiagnosticReports" ]
}

@test "old sockets, pipes and links in the temp dir are left alone" {
  aged_file "$SANDBOX_TMP/ancient.bin" 30
  make_file "$OUTSIDE/target.txt" 4
  ln -s "$OUTSIDE/target.txt" "$SANDBOX_TMP/old-link"
  ln -s "$OUTSIDE" "$SANDBOX_TMP/old-dir-link"
  mkfifo "$SANDBOX_TMP/old-pipe"
  age_path "$SANDBOX_TMP/old-link" 30
  age_path "$SANDBOX_TMP/old-dir-link" 30
  age_path "$SANDBOX_TMP/old-pipe" 30
  age_path "$OUTSIDE/target.txt" 30
  scan_for_token
  [ "$(json cat temp-files item_count)" = "1" ]
  clean_categories temp-files
  [ "$(json res temp-files status)" = "cleaned" ]
  assert_exists "$SANDBOX_TMP/old-link"
  assert_exists "$SANDBOX_TMP/old-dir-link"
  assert_exists "$SANDBOX_TMP/old-pipe"
  assert_exists "$OUTSIDE/target.txt"
}

@test "a file refreshed after the scan survives the clean" {
  aged_file "$SANDBOX_TMP/ancient.bin" 30
  aged_file "$SANDBOX_TMP/revived.bin" 30
  scan_for_token
  touch "$SANDBOX_TMP/revived.bin"
  clean_categories temp-files
  [ "$status" -eq 0 ]
  assert_missing "$SANDBOX_TMP/ancient.bin"
  assert_exists "$SANDBOX_TMP/revived.bin"
}
