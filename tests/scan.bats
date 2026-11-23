#!/usr/bin/env bats

load helpers/common

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

MAC_CATEGORIES="app-caches,temp-files,logs,ios-updates,trash,browser-chrome,browser-edge,browser-firefox,browser-brave,browser-opera,browser-arc,browser-safari,npm-cache,yarn-cache,pnpm-store,pip-cache,gradle-cache,cargo-cache,go-cache,docker-dangling,homebrew-cache,cocoapods-cache,xcode-derived-data,xcode-device-support,xcode-simulators-unavailable"

@test "scan prints one schema-valid JSON document" {
  make_chrome_profile
  run_cleanup scan
  [ "$status" -eq 0 ]
  assert_json_schema scan
  [ "${#lines[@]}" -eq 1 ]
}

@test "every macOS category appears in a fixed order" {
  run_cleanup scan
  [ "$(json ids)" = "$MAC_CATEGORIES" ]
}

@test "--deep appends node-modules-stale with its buckets" {
  run_cleanup scan --deep
  assert_json_schema scan
  [ "$(json ids)" = "$MAC_CATEGORIES,node-modules-stale" ]
  [ "$(json cat node-modules-stale status)" = "empty" ]
  [ "$(json cat node-modules-stale recommended)" = "false" ]
  [ "$(json cat node-modules-stale risk)" = "rebuild_needed" ]
}

@test "an empty home reports absent apps as not_found" {
  run_cleanup scan
  [ "$(json cat browser-chrome status)" = "not_found" ]
  [ "$(json cat npm-cache status)" = "not_found" ]
  [ "$(json cat docker-dangling status)" = "not_found" ]
  [ "$(json cat xcode-simulators-unavailable status)" = "not_found" ]
  [ "$(json get recommended_total_bytes)" = "0" ]
}

@test "chrome caches are measured across all profiles" {
  make_chrome_profile Default
  make_chrome_profile "Profile 1"
  run_cleanup scan
  [ "$(json cat browser-chrome status)" = "ok" ]
  [ "$(json cat browser-chrome item_count)" = "6" ]
  [ "$(json cat browser-chrome size_bytes)" -ge $((32 * 1024)) ]
  [ "$(json cat browser-chrome group)" = "browser" ]
}

@test "firefox counts only cache2 and startupCache" {
  local profile="$SANDBOX_HOME/Library/Caches/Firefox/Profiles/abc.default"
  make_file "$profile/cache2/entries/one" 4
  make_file "$profile/startupCache/two" 4
  make_file "$profile/safebrowsing/three" 4
  run_cleanup scan
  [ "$(json cat browser-firefox status)" = "ok" ]
  [ "$(json cat browser-firefox item_count)" = "2" ]
}

@test "an existing but empty cache is reported as empty" {
  mkdir -p "$SANDBOX_HOME/Library/Caches/Google/Chrome/Default/Cache"
  run_cleanup scan
  [ "$(json cat browser-chrome status)" = "empty" ]
  [ "$(json cat browser-chrome size_bytes)" = "0" ]
}

@test "recommended_total_bytes sums ok and recommended categories only" {
  make_chrome_profile
  make_file "$SANDBOX_HOME/.Trash/discarded.bin" 64
  make_file "$SANDBOX_HOME/Library/Caches/com.example.editor/data.bin" 16
  run_cleanup scan
  [ "$(json cat trash status)" = "ok" ]
  [ "$(json get recommended_total_bytes)" = "$(json recommended-sum)" ]
  [ "$(json get recommended_total_bytes)" -gt 0 ]
}

@test "trash is irreversible, not recommended and needs its flag" {
  make_file "$SANDBOX_HOME/.Trash/discarded.bin" 8
  run_cleanup scan
  [ "$(json cat trash risk)" = "irreversible" ]
  [ "$(json cat trash recommended)" = "false" ]
  [ "$(json cat trash requires_flag)" = "--empty-trash" ]
  [ "$(json cat browser-chrome requires_flag)" = "null" ]
}

@test "scan deletes nothing" {
  make_chrome_profile
  make_file "$SANDBOX_HOME/.Trash/discarded.bin" 8
  make_file "$SANDBOX_TMP/old-temp.bin" 8
  age_path "$SANDBOX_TMP/old-temp.bin" 30
  make_file "$SANDBOX_HOME/Library/Logs/old.log" 8
  age_path "$SANDBOX_HOME/Library/Logs/old.log" 30
  make_project "$SANDBOX_HOME/code/idle-app" 200
  local before
  before=$(snapshot_tree)
  run_cleanup scan --deep
  [ "$status" -eq 0 ]
  [ "$before" = "$(snapshot_tree)" ]
}

@test "the state directory is private" {
  run_cleanup scan
  [ "$(stat -f '%Lp' "$STATE_DIR")" = "700" ]
  [ "$(stat -f '%Lp' "$STATE_DIR/state")" = "600" ]
}

@test "app-caches does not double count folders owned by other categories" {
  make_chrome_profile
  make_file "$SANDBOX_HOME/Library/Caches/Homebrew/downloads/bottle.tar" 8
  make_file "$SANDBOX_HOME/Library/Caches/pip/wheel.whl" 8
  make_file "$SANDBOX_HOME/Library/Caches/com.example.editor/one.bin" 8
  make_file "$SANDBOX_HOME/Library/Caches/com.example.editor/deep/two.bin" 8
  run_cleanup scan
  [ "$(json cat app-caches status)" = "ok" ]
  [ "$(json cat app-caches item_count)" = "2" ]
}

@test "app-caches leaves out the folders of running apps" {
  make_file "$SANDBOX_HOME/Library/Caches/com.example.chat/one.bin" 8
  make_file "$SANDBOX_HOME/Library/Caches/com.example.chat.ShipIt/two.bin" 8
  make_file "$SANDBOX_HOME/Library/Caches/ChatApp/three.bin" 8
  make_file "$SANDBOX_HOME/Library/Caches/com.example.editor/four.bin" 8
  mark_app_running ChatApp com.example.chat
  run_cleanup scan
  [ "$(json cat app-caches item_count)" = "1" ]
}

@test "a running browser is reported as skipped_running" {
  make_chrome_profile
  mark_running "Google Chrome"
  run_cleanup scan
  [ "$(json cat browser-chrome status)" = "skipped_running" ]
  [ "$(json get recommended_total_bytes)" = "0" ]
}

@test "an unreadable trash is skipped_no_permission, not a crash" {
  make_file "$SANDBOX_HOME/.Trash/discarded.bin" 8
  chmod 000 "$SANDBOX_HOME/.Trash"
  run_cleanup scan
  [ "$status" -eq 0 ]
  [ "$(json cat trash status)" = "skipped_no_permission" ]
}

@test "safari without Full Disk Access is skipped_no_permission" {
  local container="$SANDBOX_HOME/Library/Containers/com.apple.Safari"
  make_file "$container/Data/Library/Caches/com.apple.Safari/WebKitCache/blob" 8
  chmod 000 "$container/Data"
  run_cleanup scan
  [ "$(json cat browser-safari status)" = "skipped_no_permission" ]
}

@test "a safari container without a data folder is not a permission problem" {
  mkdir -p "$SANDBOX_HOME/Library/Containers/com.apple.Safari"
  run_cleanup scan
  [ "$(json cat browser-safari status)" = "not_found" ]
}

@test "an unlistable safari container is skipped_no_permission" {
  local container="$SANDBOX_HOME/Library/Containers/com.apple.Safari"
  make_file "$container/Data/Library/Caches/com.apple.Safari/WebKitCache/blob" 8
  chmod 000 "$container"
  run_cleanup scan
  [ "$(json cat browser-safari status)" = "skipped_no_permission" ]
}

@test "a browser with a profile folder but no cache folders is not a permission problem" {
  local vendor
  for vendor in "Google/Chrome" "Microsoft Edge" "BraveSoftware/Brave-Browser" \
    "com.operasoftware.Opera" "Arc/User Data" "Firefox/Profiles/abc.default"; do
    make_file "$SANDBOX_HOME/Library/Application Support/$vendor/Default/Cookies" 4
  done
  mkdir -p "$SANDBOX_HOME/Library/Containers/com.apple.Safari/Data/Library"
  run_cleanup scan
  local id
  for id in chrome edge brave opera arc firefox safari; do
    [ "$(json cat "browser-$id" status)" = "not_found" ] || { echo "$id: $(json cat "browser-$id" status)"; return 1; }
  done
}

@test "a file name with a line break is counted once" {
  local cache="$SANDBOX_HOME/Library/Caches/com.example.editor"
  make_file "$cache/plain.bin" 8
  make_file "$cache/broken"$'\n'"12345 16 -rw-r--r-- 1 someone staff 4096 Jan 1 2020 tail.bin" 8
  run_cleanup scan
  [ "$(json cat app-caches item_count)" = "2" ]
  [ "$(json cat app-caches size_bytes)" = "$((16 * 1024))" ]
}

@test "safari counts only its WebKit cache when readable" {
  local caches="$SANDBOX_HOME/Library/Containers/com.apple.Safari/Data/Library/Caches"
  make_file "$caches/com.apple.Safari/WebKitCache/blob" 8
  make_file "$caches/com.apple.Safari/TabSnapshots/snapshot" 8
  run_cleanup scan
  [ "$(json cat browser-safari status)" = "ok" ]
  [ "$(json cat browser-safari item_count)" = "1" ]
}

@test "npm cache without npm on PATH is still measured" {
  make_file "$SANDBOX_HOME/.npm/_cacache/content/blob" 8
  run_cleanup scan
  [ "$(json cat npm-cache status)" = "ok" ]
  [ "$(json cat npm-cache item_count)" = "1" ]
  [ ! -s "$STUB_LOG" ]
}

@test "pnpm store without pnpm installed is not_found" {
  make_file "$SANDBOX_HOME/Library/pnpm/store/v3/files/blob" 8
  run_cleanup scan
  [ "$(json cat pnpm-store status)" = "not_found" ]
}

@test "scan never runs a cleaning command of a developer tool" {
  local tool
  for tool in yarn pip3 go brew pod; do stub_tool "$tool"; done
  stub_cache_tool npm "config get cache" "$SANDBOX_HOME/.npm"
  stub_cache_tool pnpm "store path" "$SANDBOX_HOME/Library/pnpm/store/v3"
  make_file "$SANDBOX_HOME/.npm/_cacache/content/blob" 8
  make_file "$SANDBOX_HOME/Library/pnpm/store/v3/files/blob" 8
  run_cleanup scan
  [ "$(json cat pnpm-store status)" = "ok" ]
  [ "$(json cat npm-cache status)" = "ok" ]
  ! grep -qE "clean|purge|prune|cleanup" "$STUB_LOG"
}

@test "docker with a stopped daemon is unavailable" {
  stub_tool docker 'exit 1'
  run_cleanup scan
  [ "$(json cat docker-dangling status)" = "unavailable" ]
}

@test "dangling docker images are counted with an unknown size" {
  stub_tool docker 'case "$1" in images) echo aaa111; echo bbb222 ;; esac'
  run_cleanup scan
  [ "$(json cat docker-dangling status)" = "ok" ]
  [ "$(json cat docker-dangling item_count)" = "2" ]
  [ "$(json cat docker-dangling size_bytes)" = "null" ]
  ! grep -q prune "$STUB_LOG"
}

@test "docker without dangling images is empty" {
  stub_tool docker
  run_cleanup scan
  [ "$(json cat docker-dangling status)" = "empty" ]
}

@test "unavailable simulators are counted through simctl" {
  stub_tool xcrun 'case "$*" in
    "simctl list devices unavailable")
      echo "== Devices =="
      echo "    iPhone 11 (8E7A1B2C-1111-2222-3333-444455556666) (Shutdown) (unavailable)"
      echo "    iPad Air (9F7A1B2C-1111-2222-3333-444455556666) (Shutdown) (unavailable)" ;;
  esac'
  run_cleanup scan
  [ "$(json cat xcode-simulators-unavailable status)" = "ok" ]
  [ "$(json cat xcode-simulators-unavailable item_count)" = "2" ]
  [ "$(json cat xcode-simulators-unavailable size_bytes)" = "null" ]
  ! grep -q delete "$STUB_LOG"
}

@test "device support counts only folders untouched for 90 days" {
  local support="$SANDBOX_HOME/Library/Developer/Xcode/iOS DeviceSupport"
  make_file "$support/15.0 (19A346)/Symbols/dyld" 8
  make_file "$support/17.0 (21A329)/Symbols/dyld" 8
  age_tree "$support/15.0 (19A346)" 120
  run_cleanup scan
  [ "$(json cat xcode-device-support status)" = "ok" ]
  [ "$(json cat xcode-device-support item_count)" = "1" ]
}

@test "a temp dir inside the home directory is never treated as temp" {
  make_file "$SANDBOX_HOME/Documents/old-report.txt" 8
  age_path "$SANDBOX_HOME/Documents/old-report.txt" 60
  run env -i HOME="$SANDBOX_HOME" TMPDIR="$SANDBOX_HOME/Documents" \
    PATH="$STUB_BIN:$TOOL_BIN:/bin" /bin/bash "$CLEANUP" scan
  [ "$status" -eq 0 ]
  [ "$(json cat temp-files status)" = "not_found" ]
}

@test "only genuine per-user temp locations are accepted as temp root" {
  run_function temp_root_is_sane /private/tmp
  [ "$status" -ne 0 ]
  run_function temp_root_is_sane /Volumes/External/stuff
  [ "$status" -ne 0 ]
  run_function temp_root_is_sane "$SANDBOX_HOME"
  [ "$status" -ne 0 ]
  run_function temp_root_is_sane "$SANDBOX_TMP"
  [ "$status" -eq 0 ]
}

@test "disk totals are reported as positive integers" {
  run_cleanup scan
  [ "$(json get disk.total_bytes)" -gt 0 ]
  [ "$(json get disk.free_bytes)" -gt 0 ]
}

@test "app-caches never includes caches of system services" {
  make_file "$SANDBOX_HOME/Library/Caches/com.apple.bird/session.db" 8
  make_file "$SANDBOX_HOME/Library/Caches/CloudKit/records.db" 8
  make_file "$SANDBOX_HOME/Library/Caches/com.example.editor/data.bin" 8
  scan_for_token
  [ "$(json cat app-caches item_count)" = "1" ]
  clean_categories app-caches
  [ "$(json res app-caches status)" = "cleaned" ]
  assert_exists "$SANDBOX_HOME/Library/Caches/com.apple.bird/session.db"
  assert_exists "$SANDBOX_HOME/Library/Caches/CloudKit/records.db"
}

@test "a tool that hangs is stopped instead of blocking the scan" {
  mkdir -p "$STATE_DIR"
  run_function run_tool 1 /bin/sleep 30
  [ "$status" -eq 124 ]
}

@test "tool commands never run inside the caller's working directory" {
  stub_tool docker "/bin/pwd >> '$SANDBOX/docker-cwd'"
  cd "$SANDBOX_HOME"
  run_cleanup scan
  [ "$(sort -u "$SANDBOX/docker-cwd")" = "$STATE_DIR" ]
}
