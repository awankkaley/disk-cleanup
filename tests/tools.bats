#!/usr/bin/env bats

load helpers/common

setup() {
  setup_sandbox
  DOCS="$SANDBOX_HOME/Documents"
  make_file "$DOCS/thesis.docx" 8
  make_file "$DOCS/_cacache/keep.bin" 8
  CACHES="$SANDBOX_HOME/Library/Caches"
}
teardown() { teardown_sandbox; }

# tool|category|report arguments|clean arguments|default cache dir (below HOME)
TOOL_TABLE=(
  "npm|npm-cache|config get cache|cache clean --force|.npm"
  "yarn|yarn-cache|cache dir|cache clean|Library/Caches/Yarn"
  "pnpm|pnpm-store|store path|store prune|Library/pnpm/store"
  "pip3|pip-cache|cache dir|cache purge|Library/Caches/pip"
  "go|go-cache|env GOCACHE|clean -cache|Library/Caches/go-build"
  "brew|homebrew-cache|--cache|cleanup -s|Library/Caches/Homebrew"
)

split_row() {
  local rest=$1
  T_TOOL=${rest%%|*} rest=${rest#*|}
  T_ID=${rest%%|*} rest=${rest#*|}
  T_REPORT=${rest%%|*} rest=${rest#*|}
  T_CLEAN=${rest%%|*}
  T_DEFAULT="$SANDBOX_HOME/${rest#*|}"
}

plant_default() {
  if [ "$T_TOOL" = npm ]; then
    make_file "$T_DEFAULT/_cacache/content/blob" 8
  else
    make_file "$T_DEFAULT/v1/blob" 8
  fi
}

@test "scan: a tool whose cache lives in Documents is unavailable and nothing runs" {
  local row
  for row in "${TOOL_TABLE[@]}"; do
    split_row "$row"
    plant_default
    stub_cache_tool "$T_TOOL" "$T_REPORT" "$DOCS" "/bin/rm -rf '$DOCS'"
  done
  run_cleanup scan
  [ "$status" -eq 0 ]
  assert_json_schema scan
  for row in "${TOOL_TABLE[@]}"; do
    split_row "$row"
    [ "$(json cat "$T_ID" status)" = "unavailable" ] || { echo "$T_ID: $(json cat "$T_ID" status)"; return 1; }
    ! grep -qx "$T_TOOL $T_CLEAN" "$STUB_LOG"
  done
  [ "$(json get recommended_total_bytes)" = "0" ]
  assert_exists "$DOCS/thesis.docx"
}

@test "clean: a cache relocated to Documents after the scan is CUSTOM_LOCATION and the sentinel survives" {
  local row ids=""
  for row in "${TOOL_TABLE[@]}"; do
    split_row "$row"
    plant_default
    stub_cache_tool "$T_TOOL" "$T_REPORT" "$T_DEFAULT"
    ids="$ids${ids:+,}$T_ID"
  done
  scan_for_token
  for row in "${TOOL_TABLE[@]}"; do
    split_row "$row"
    [ "$(json cat "$T_ID" status)" = "ok" ] || { echo "$T_ID: $(json cat "$T_ID" status)"; return 1; }
    stub_cache_tool "$T_TOOL" "$T_REPORT" "$DOCS" "/bin/rm -rf '$DOCS'"
  done
  : > "$STUB_LOG"
  clean_categories "$ids"
  [ "$status" -eq 0 ]
  assert_json_schema clean
  for row in "${TOOL_TABLE[@]}"; do
    split_row "$row"
    [ "$(json res "$T_ID" status)" = "unavailable" ] || { echo "$T_ID: $(json res "$T_ID" status)"; return 1; }
    [ "$(json res "$T_ID" error_code)" = "CUSTOM_LOCATION" ]
    [ "$(json res "$T_ID" freed_bytes)" = "0" ]
    ! grep -qx "$T_TOOL $T_CLEAN" "$STUB_LOG"
    [ -n "$(find "$T_DEFAULT" -name blob)" ]
  done
  [ "$(json get freed_total_bytes)" = "0" ]
  assert_exists "$DOCS/thesis.docx"
  assert_exists "$DOCS/_cacache/keep.bin"
}

@test "a cache dir outside the home directory is CUSTOM_LOCATION" {
  make_file "$OUTSIDE/yarn/blob" 8
  make_file "$CACHES/Yarn/v6/blob" 8
  stub_cache_tool yarn "cache dir" "$OUTSIDE/yarn" "/bin/rm -rf '$OUTSIDE/yarn'"
  run_cleanup scan
  [ "$(json cat yarn-cache status)" = "unavailable" ]
  assert_exists "$OUTSIDE/yarn/blob"
}

@test "a default cache dir that is a symlink into Documents is CUSTOM_LOCATION" {
  mkdir -p "$CACHES"
  ln -s "$DOCS" "$CACHES/Yarn"
  stub_cache_tool yarn "cache dir" "$CACHES/Yarn" "/bin/rm -rf '$DOCS'"
  run_cleanup scan
  [ "$(json cat yarn-cache status)" = "unavailable" ]
  ! grep -qx "yarn cache clean" "$STUB_LOG"
  assert_exists "$DOCS/thesis.docx"
}

@test "a cache dir below the default location is accepted and the official command runs" {
  make_file "$CACHES/Yarn/v6/blob" 8
  stub_cache_tool yarn "cache dir" "$CACHES/Yarn/v6" "/bin/rm -rf '$CACHES/Yarn/v6'"
  scan_for_token
  [ "$(json cat yarn-cache status)" = "ok" ]
  ! grep -qx "yarn cache clean" "$STUB_LOG"
  clean_categories yarn-cache
  [ "$(json res yarn-cache status)" = "cleaned" ]
  [ "$(json res yarn-cache error_code)" = "null" ]
  [ "$(json res yarn-cache freed_bytes)" -ge 8192 ]
  grep -qx "yarn cache clean" "$STUB_LOG"
}

@test "a tool that cannot report its dir is never run; the default dir is deleted by the guard" {
  make_file "$CACHES/Yarn/v6/blob" 8
  make_file "$SANDBOX/sentinel" 4
  stub_tool yarn "case \"\$*\" in 'cache dir') exit 1 ;; esac; /bin/rm -f '$SANDBOX/sentinel'"
  scan_for_token
  [ "$(json cat yarn-cache status)" = "ok" ]
  clean_categories yarn-cache
  [ "$(json res yarn-cache status)" = "cleaned" ]
  ! grep -qx "yarn cache clean" "$STUB_LOG"
  assert_exists "$SANDBOX/sentinel"
  [ -d "$CACHES/Yarn" ]
  assert_missing "$CACHES/Yarn/v6"
}

@test "a tool that prints something that is not one absolute path cannot report its dir" {
  make_file "$CACHES/go-build/aa/object" 8
  stub_tool go "case \"\$*\" in 'env GOCACHE') echo off ;; *) /bin/rm -rf '$DOCS' ;; esac"
  scan_for_token
  clean_categories go-cache
  [ "$(json res go-cache status)" = "cleaned" ]
  ! grep -qx "go clean -cache" "$STUB_LOG"
  assert_exists "$DOCS/thesis.docx"
  assert_missing "$CACHES/go-build/aa"
}

@test "pnpm that cannot report its store is unavailable and never pruned" {
  make_file "$SANDBOX_HOME/Library/pnpm/store/v3/files/blob" 8
  stub_tool pnpm "exit 1"
  run_cleanup scan
  [ "$(json cat pnpm-store status)" = "unavailable" ]
  ! grep -qx "pnpm store prune" "$STUB_LOG"
  assert_exists "$SANDBOX_HOME/Library/pnpm/store/v3/files/blob"
}

@test "cocoapods is cleaned by the guarded delete only; pod is never run" {
  make_file "$CACHES/CocoaPods/Pods/spec" 8
  stub_tool pod "/bin/rm -rf '$DOCS'"
  scan_for_token
  [ "$(json cat cocoapods-cache status)" = "ok" ]
  clean_categories cocoapods-cache
  [ "$(json res cocoapods-cache status)" = "cleaned" ]
  [ ! -s "$STUB_LOG" ]
  assert_exists "$DOCS/thesis.docx"
  assert_missing "$CACHES/CocoaPods/Pods"
}

@test "pnpm store size is unknown at scan and measured after cleaning" {
  make_file "$SANDBOX_HOME/Library/pnpm/store/v3/files/unreferenced" 64
  make_file "$SANDBOX_HOME/Library/pnpm/store/v3/files/referenced" 64
  make_chrome_profile
  stub_cache_tool pnpm "store path" "$SANDBOX_HOME/Library/pnpm/store/v3" \
    "/bin/rm -f '$SANDBOX_HOME/Library/pnpm/store/v3/files/unreferenced'"
  scan_for_token
  assert_json_schema scan
  [ "$(json cat pnpm-store status)" = "ok" ]
  [ "$(json cat pnpm-store size_bytes)" = "null" ]
  [ "$(json cat pnpm-store item_count)" = "null" ]
  [ "$(json cat pnpm-store recommended)" = "true" ]
  [ "$(json get recommended_total_bytes)" = "$(json cat browser-chrome size_bytes)" ]
  case "$(json cat pnpm-store impact)" in
    *"no project references"*"after cleaning"*) ;;
    *) return 1 ;;
  esac
  clean_categories pnpm-store
  [ "$(json res pnpm-store status)" = "cleaned" ]
  [ "$(json res pnpm-store freed_bytes)" -ge $((64 * 1024)) ]
  [ "$(json res pnpm-store freed_bytes)" -lt $((128 * 1024)) ]
  assert_exists "$SANDBOX_HOME/Library/pnpm/store/v3/files/referenced"
}

@test "an empty pnpm store is empty" {
  mkdir -p "$SANDBOX_HOME/Library/pnpm/store/v3"
  stub_cache_tool pnpm "store path" "$SANDBOX_HOME/Library/pnpm/store/v3"
  run_cleanup scan
  [ "$(json cat pnpm-store status)" = "empty" ]
}

@test "result error codes: not_found, tool failed, guard refused" {
  make_project "$SANDBOX_HOME/code/idle-app" 200
  make_file "$SANDBOX_HOME/Library/pnpm/store/v3/files/blob" 8
  stub_cache_tool pnpm "store path" "$SANDBOX_HOME/Library/pnpm/store/v3" "exit 1"
  make_file "$OUTSIDE/gradle/caches/modules-2/artifact.jar" 8
  ln -s "$OUTSIDE/gradle" "$SANDBOX_HOME/.gradle"
  stub_tool docker 'case "$1" in images) echo aaa111 ;; esac'
  scan_for_token --deep
  touch "$SANDBOX_HOME/code/idle-app/src/index.js"
  stub_tool docker 'exit 1'
  clean_categories node-modules-stale,pnpm-store,gradle-cache,docker-dangling
  assert_json_schema clean
  [ "$(json res node-modules-stale status)" = "not_found" ]
  [ "$(json res node-modules-stale error_code)" = "NOT_FOUND" ]
  [ "$(json res pnpm-store status)" = "failed" ]
  [ "$(json res pnpm-store error_code)" = "TOOL_FAILED" ]
  [ "$(json res gradle-cache status)" = "failed" ]
  [ "$(json res gradle-cache error_code)" = "GUARD_REFUSED" ]
  [ "$(json res docker-dangling status)" = "unavailable" ]
  [ "$(json res docker-dangling error_code)" = "TOOL_UNAVAILABLE" ]
  assert_exists "$OUTSIDE/gradle/caches/modules-2/artifact.jar"
}

@test "result error codes: running app, permission, partial" {
  local cache="$CACHES/com.example.editor"
  make_chrome_profile
  make_file "$cache/free/data.bin" 8
  make_file "$cache/locked/data.bin" 8
  make_file "$SANDBOX_HOME/.gradle/caches/locked/artifact.jar" 8
  chmod 500 "$cache/locked" "$SANDBOX_HOME/.gradle/caches/locked" "$SANDBOX_HOME/.gradle/caches"
  scan_for_token
  mark_running "Google Chrome"
  clean_categories browser-chrome,app-caches,gradle-cache
  assert_json_schema clean
  [ "$(json res browser-chrome error_code)" = "APP_RUNNING" ]
  [ "$(json res app-caches error_code)" = "SOME_ITEMS_REMAIN" ]
  [ "$(json res gradle-cache status)" = "skipped_no_permission" ]
  [ "$(json res gradle-cache error_code)" = "PERMISSION_DENIED" ]
}
