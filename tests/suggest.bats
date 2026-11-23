#!/usr/bin/env bats

load helpers/common

setup() {
  setup_sandbox
  make_file "$SANDBOX_HOME/Library/Logs/old-one.log" 64
  age_path "$SANDBOX_HOME/Library/Logs/old-one.log" 30
  make_file "$SANDBOX_TMP/stale/old-two.bin" 256
  age_path "$SANDBOX_TMP/stale/old-two.bin" 30
  make_file "$SANDBOX_HOME/Library/Caches/some-app/blob" 512
  make_file "$SANDBOX_HOME/.cargo/registry/cache/crate.bin" 1024
  make_file "$SANDBOX_HOME/.Trash/discarded.bin" 2048
}
teardown() { teardown_sandbox; }

suggest() { run_function suggestion_json "$@"; }

@test "every category reports a static rebuild cost" {
  run_cleanup scan --deep
  assert_json_schema scan
  [ "$(json cat temp-files rebuild_cost)" = "1" ]
  [ "$(json cat logs rebuild_cost)" = "1" ]
  [ "$(json cat app-caches rebuild_cost)" = "2" ]
  [ "$(json cat npm-cache rebuild_cost)" = "2" ]
  [ "$(json cat ios-updates rebuild_cost)" = "2" ]
  [ "$(json cat xcode-derived-data rebuild_cost)" = "3" ]
  [ "$(json cat node-modules-stale rebuild_cost)" = "3" ]
}

@test "without --target-gb there is no suggestion" {
  run_cleanup scan
  assert_json_schema scan
  [ "$(json get suggestion)" = "null" ]
  [[ "$output" != *suggestion* ]]
}

@test "a target that cannot be reached lists every candidate, cheapest rebuild first" {
  run_cleanup scan --target-gb 1
  [ "$status" -eq 0 ]
  assert_json_schema scan
  [ "$(json get suggestion.target_bytes)" = "1073741824" ]
  [ "$(json get suggestion.reaches_target)" = "false" ]
  [ "$(json get suggestion.category_ids)" = '["temp-files","logs","app-caches","cargo-cache"]' ]
  [ "$(json get suggestion.total_bytes)" = "$(json recommended-sum)" ]
}

@test "the suggestion never contains the trash or a skipped category" {
  make_chrome_profile
  mark_running "Google Chrome"
  run_cleanup scan --target-gb 5
  assert_json_schema scan
  [ "$(json cat browser-chrome status)" = "skipped_running" ]
  [[ "$(json get suggestion.category_ids)" != *trash* ]]
  [[ "$(json get suggestion.category_ids)" != *browser-chrome* ]]
}

@test "candidates are taken until the target is reached" {
  suggest 100 $'1 60 logs\n2 500 npm-cache\n1 70 temp-files\n3 900 cargo-cache'
  [ "$status" -eq 0 ]
  [ "$output" = '{"target_bytes":100,"category_ids":["temp-files","logs"],"total_bytes":130,"reaches_target":true}' ]
}

@test "one large cheap category is enough" {
  suggest 100 $'1 60 logs\n1 170 temp-files'
  [ "$output" = '{"target_bytes":100,"category_ids":["temp-files"],"total_bytes":170,"reaches_target":true}' ]
}

@test "a lower rebuild cost beats a larger size" {
  suggest 1000 $'3 900 cargo-cache\n2 500 npm-cache\n2 700 pip-cache\n1 10 logs'
  [ "$output" = '{"target_bytes":1000,"category_ids":["logs","pip-cache","npm-cache"],"total_bytes":1210,"reaches_target":true}' ]
}

@test "no candidates gives an empty suggestion" {
  suggest 100 ""
  [ "$output" = '{"target_bytes":100,"category_ids":[],"total_bytes":0,"reaches_target":false}' ]
}

@test "--target-gb accepts only whole numbers from 1 to 10000" {
  local bad
  for bad in 0 10001 -1 1.5 ten "" 99999999999999999999; do
    run_cleanup scan --target-gb "$bad"
    assert_error INVALID_ARGUMENT
  done
  run_cleanup scan --target-gb
  assert_error USAGE 2
  run_cleanup scan --target-gb 10000
  [ "$status" -eq 0 ]
  [ "$(json get suggestion.target_bytes)" = "10737418240000" ]
}

@test "the suggestion approves nothing: clean still needs explicit categories" {
  scan_for_token --target-gb 1
  run_cleanup clean --token "$TOKEN"
  assert_error USAGE 2
  assert_exists "$SANDBOX_HOME/Library/Caches/some-app/blob"
}

@test "scan with a target leaks no names" {
  run_cleanup scan --target-gb 2
  assert_private old-one old-two some-app crate.bin discarded
}
