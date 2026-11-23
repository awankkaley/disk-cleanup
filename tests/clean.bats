#!/usr/bin/env bats

load helpers/common

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

plant_sentinels() {
  SENTINELS=(
    "$SANDBOX_HOME/Documents/thesis.docx"
    "$SANDBOX_HOME/Documents/Cache/keep.bin"
    "$SANDBOX_HOME/Desktop/todo.txt"
    "$SANDBOX_HOME/Downloads/installer.dmg"
    "$SANDBOX_HOME/Pictures/holiday.jpg"
    "$SANDBOX_HOME/Movies/clip.mov"
    "$SANDBOX_HOME/Music/song.mp3"
    "$SANDBOX_HOME/Library/Mobile Documents/com~apple~CloudDocs/note.txt"
    "$SANDBOX_HOME/Library/Developer/Xcode/Archives/2026-01-01/App.xcarchive/Info.plist"
    "$SANDBOX_HOME/Library/Developer/Xcode/UserData/keybindings.plist"
    "$SANDBOX_HOME/Library/Application Support/SomeApp/database.sqlite"
    "$SANDBOX_HOME/Library/Preferences/com.example.plist"
    "$SANDBOX_HOME/Library/Keychains/login.keychain-db"
    "$SANDBOX_HOME/.ssh/id_ed25519"
    "$SANDBOX_HOME/.gradle/gradle.properties"
    "$SANDBOX_HOME/.cargo/bin/tool"
    "$SANDBOX_HOME/.cargo/registry/index/cache-index"
    "$SANDBOX_HOME/.npm/_logs/debug.log"
    "$SANDBOX_HOME/code/active-app/node_modules/pkg/index.js"
    "$SANDBOX_HOME/code/active-app/package.json"
    "$SANDBOX_HOME/code/active-app/package-lock.json"
    "$SANDBOX_TMP/fresh-temp.bin"
    "$SANDBOX_HOME/Library/Logs/fresh.log"
    "$OUTSIDE/elsewhere.txt"
  )
  local sentinel
  for sentinel in "${SENTINELS[@]}"; do make_file "$sentinel" 4; done
}

plant_cleanable() {
  make_chrome_profile
  make_file "$SANDBOX_HOME/Library/Caches/com.example.editor/data.bin" 8
  make_file "$SANDBOX_HOME/.Trash/discarded.bin" 8
  make_file "$SANDBOX_TMP/old-temp.bin" 8
  age_path "$SANDBOX_TMP/old-temp.bin" 30
  make_file "$SANDBOX_HOME/Library/Logs/DiagnosticReports/old.crash" 8
  age_path "$SANDBOX_HOME/Library/Logs/DiagnosticReports/old.crash" 30
  make_file "$SANDBOX_HOME/.npm/_cacache/content/blob" 8
  make_file "$SANDBOX_HOME/Library/Caches/Yarn/v6/blob" 8
  make_file "$SANDBOX_HOME/Library/Caches/pip/wheel.whl" 8
  make_file "$SANDBOX_HOME/Library/Caches/go-build/aa/object" 8
  make_file "$SANDBOX_HOME/Library/Caches/Homebrew/downloads/bottle.tar" 8
  make_file "$SANDBOX_HOME/Library/Caches/CocoaPods/Pods/spec" 8
  make_file "$SANDBOX_HOME/.gradle/caches/modules-2/artifact.jar" 8
  make_file "$SANDBOX_HOME/.cargo/registry/cache/index/crate.crate" 8
  make_file "$SANDBOX_HOME/.cargo/registry/src/index/crate/lib.rs" 8
  make_file "$SANDBOX_HOME/Library/Developer/Xcode/DerivedData/App-abc/Build/object.o" 8
  make_file "$SANDBOX_HOME/Library/Developer/Xcode/iOS DeviceSupport/15.0/Symbols/dyld" 8
  age_tree "$SANDBOX_HOME/Library/Developer/Xcode/iOS DeviceSupport/15.0" 120
  make_project "$SANDBOX_HOME/code/idle-app" 200
}

@test "cleaning every ok category removes only allowlisted data" {
  plant_cleanable
  plant_sentinels
  scan_for_token --deep
  local ok_ids
  ok_ids=$(json ok-ids)
  [ "$(echo "$ok_ids" | tr ',' '\n' | wc -l)" -ge 16 ]
  clean_categories "$ok_ids" --empty-trash
  [ "$status" -eq 0 ]
  assert_json_schema clean
  local sentinel
  for sentinel in "${SENTINELS[@]}"; do assert_exists "$sentinel"; done
  for sentinel in Cookies History "Login Data" Bookmarks Sessions/session-file \
    Extensions/ext-id/manifest.json "Service Worker/CacheStorage/sw-blob"; do
    assert_exists "$CHROME_DATA/$sentinel"
  done
  assert_missing "$SANDBOX_HOME/.Trash/discarded.bin"
  assert_missing "$SANDBOX_TMP/old-temp.bin"
  assert_missing "$SANDBOX_HOME/Library/Logs/DiagnosticReports/old.crash"
  assert_missing "$SANDBOX_HOME/code/idle-app/node_modules"
  assert_exists "$SANDBOX_HOME/code/idle-app/src/index.js"
  assert_missing "$SANDBOX_HOME/.gradle/caches/modules-2"
  [ "$(json get freed_total_bytes)" -gt 0 ]
}

@test "chrome clean empties the cache folders but keeps them and the profile" {
  make_chrome_profile
  scan_for_token
  clean_categories browser-chrome
  [ "$status" -eq 0 ]
  assert_json_schema clean
  [ "$(json res browser-chrome status)" = "cleaned" ]
  [ "$(json res browser-chrome error_code)" = "null" ]
  [ "$(json res browser-chrome freed_bytes)" -ge $((20 * 1024)) ]
  [ -d "$CHROME_CACHE/Cache" ] && [ -d "$CHROME_CACHE/Code Cache" ] && [ -d "$CHROME_DATA/GPUCache" ]
  assert_missing "$CHROME_CACHE/Cache/Cache_Data"
  assert_missing "$CHROME_DATA/GPUCache/blob-three"
  assert_exists "$CHROME_DATA/Cookies"
  assert_exists "$CHROME_DATA/Service Worker/CacheStorage/sw-blob"
}

@test "only the requested categories are cleaned, in a single result each" {
  make_chrome_profile
  make_file "$SANDBOX_HOME/Library/Caches/com.example.editor/data.bin" 8
  scan_for_token
  clean_categories browser-chrome,browser-chrome
  [ "$(json ids)" = "browser-chrome" ]
  assert_exists "$SANDBOX_HOME/Library/Caches/com.example.editor/data.bin"
}

@test "a browser started after the scan is skipped and nothing is deleted" {
  make_chrome_profile
  scan_for_token
  mark_running "Google Chrome"
  clean_categories browser-chrome
  [ "$status" -eq 0 ]
  [ "$(json res browser-chrome status)" = "skipped_running" ]
  [ "$(json res browser-chrome freed_bytes)" = "0" ]
  assert_exists "$CHROME_CACHE/Cache/Cache_Data/blob-one"
}

@test "xcode derived data is skipped while Xcode runs" {
  make_file "$SANDBOX_HOME/Library/Developer/Xcode/DerivedData/App-abc/Build/object.o" 8
  scan_for_token
  mark_running "Xcode"
  clean_categories xcode-derived-data
  [ "$(json res xcode-derived-data status)" = "skipped_running" ]
  assert_exists "$SANDBOX_HOME/Library/Developer/Xcode/DerivedData/App-abc/Build/object.o"
}

@test "gradle cache is skipped while a gradle daemon runs" {
  make_file "$SANDBOX_HOME/.gradle/caches/modules-2/artifact.jar" 8
  scan_for_token
  mark_running "GradleDaemon"
  clean_categories gradle-cache
  [ "$(json res gradle-cache status)" = "skipped_running" ]
  assert_exists "$SANDBOX_HOME/.gradle/caches/modules-2/artifact.jar"
}

@test "app-caches keeps the folders of running apps and every top-level folder" {
  make_file "$SANDBOX_HOME/Library/Caches/com.example.chat/one.bin" 8
  make_file "$SANDBOX_HOME/Library/Caches/com.example.editor/deep/two.bin" 8
  make_file "$SANDBOX_HOME/Library/Caches/ms-playwright/chromium/browser.bin" 8
  make_chrome_profile
  mark_app_running ChatApp com.example.chat
  scan_for_token
  clean_categories app-caches
  [ "$(json res app-caches status)" = "cleaned" ]
  assert_exists "$SANDBOX_HOME/Library/Caches/com.example.chat/one.bin"
  assert_exists "$SANDBOX_HOME/Library/Caches/ms-playwright/chromium/browser.bin"
  assert_exists "$CHROME_CACHE/Cache/Cache_Data/blob-one"
  [ -d "$SANDBOX_HOME/Library/Caches/com.example.editor" ]
  assert_missing "$SANDBOX_HOME/Library/Caches/com.example.editor/deep"
}

@test "trash is emptied with the flag without following links" {
  make_file "$SANDBOX_HOME/.Trash/folder/discarded.bin" 8
  make_file "$OUTSIDE/linked/keep.txt" 4
  ln -s "$OUTSIDE/linked" "$SANDBOX_HOME/.Trash/shortcut"
  scan_for_token
  clean_categories trash --empty-trash
  [ "$(json res trash status)" = "cleaned" ]
  [ -d "$SANDBOX_HOME/.Trash" ]
  assert_missing "$SANDBOX_HOME/.Trash/folder"
  assert_missing "$SANDBOX_HOME/.Trash/shortcut"
  assert_exists "$OUTSIDE/linked/keep.txt"
}

@test "npm cache uses the official command when npm is installed" {
  make_file "$SANDBOX_HOME/.npm/_cacache/content/blob" 8
  stub_cache_tool npm "config get cache" "$SANDBOX_HOME/.npm" \
    "/bin/rm -rf '$SANDBOX_HOME/.npm/_cacache/content'"
  scan_for_token
  clean_categories npm-cache
  [ "$(json res npm-cache status)" = "cleaned" ]
  [ "$(json res npm-cache freed_bytes)" -ge 8192 ]
  grep -qx "npm cache clean --force" "$STUB_LOG"
}

@test "npm cache falls back to the guarded delete without npm" {
  make_file "$SANDBOX_HOME/.npm/_cacache/content/blob" 8
  scan_for_token
  clean_categories npm-cache
  [ "$(json res npm-cache status)" = "cleaned" ]
  [ -d "$SANDBOX_HOME/.npm/_cacache" ]
  assert_missing "$SANDBOX_HOME/.npm/_cacache/content"
}

@test "a failing official command falls back to the guarded delete" {
  make_file "$SANDBOX_HOME/Library/Caches/Yarn/v6/blob" 8
  stub_cache_tool yarn "cache dir" "$SANDBOX_HOME/Library/Caches/Yarn/v6" 'exit 1'
  scan_for_token
  clean_categories yarn-cache
  [ "$(json res yarn-cache status)" = "cleaned" ]
  grep -qx "yarn cache clean" "$STUB_LOG"
  assert_missing "$SANDBOX_HOME/Library/Caches/Yarn/v6"
}

@test "pnpm only ever prunes and reports failed when prune fails" {
  make_file "$SANDBOX_HOME/Library/pnpm/store/v3/files/blob" 8
  stub_cache_tool pnpm "store path" "$SANDBOX_HOME/Library/pnpm/store/v3" 'exit 1'
  scan_for_token
  clean_categories pnpm-store
  [ "$(json res pnpm-store status)" = "failed" ]
  [ "$(json res pnpm-store error_code)" = "TOOL_FAILED" ]
  grep -qx "pnpm store prune" "$STUB_LOG"
  assert_exists "$SANDBOX_HOME/Library/pnpm/store/v3/files/blob"
}

@test "each developer tool gets exactly its documented command" {
  make_file "$SANDBOX_HOME/Library/Caches/pip/wheel.whl" 8
  make_file "$SANDBOX_HOME/Library/Caches/go-build/aa/object" 8
  make_file "$SANDBOX_HOME/Library/Caches/Homebrew/downloads/bottle.tar" 8
  make_file "$SANDBOX_HOME/Library/Caches/CocoaPods/Pods/spec" 8
  local caches="$SANDBOX_HOME/Library/Caches"
  stub_cache_tool pip3 "cache dir" "$caches/pip"
  stub_cache_tool go "env GOCACHE" "$caches/go-build"
  stub_cache_tool brew "--cache" "$caches/Homebrew"
  stub_tool pod
  scan_for_token
  : > "$STUB_LOG"
  clean_categories pip-cache,go-cache,homebrew-cache,cocoapods-cache
  [ "$status" -eq 0 ]
  [ "$(grep -vE 'cache dir|env GOCACHE|--cache' "$STUB_LOG" | sort)" = "$(printf '%s\n' \
    "brew cleanup -s" "go clean -cache" "pip3 cache purge")" ]
}

@test "cargo cache touches only registry cache and src" {
  make_file "$SANDBOX_HOME/.cargo/registry/cache/index/crate.crate" 8
  make_file "$SANDBOX_HOME/.cargo/registry/src/index/crate/lib.rs" 8
  make_file "$SANDBOX_HOME/.cargo/registry/index/cache-index" 8
  make_file "$SANDBOX_HOME/.cargo/bin/tool" 8
  make_file "$SANDBOX_HOME/.cargo/git/checkouts/repo/file" 8
  scan_for_token
  [ "$(json cat cargo-cache item_count)" = "2" ]
  clean_categories cargo-cache
  [ "$(json res cargo-cache status)" = "cleaned" ]
  assert_missing "$SANDBOX_HOME/.cargo/registry/cache/index"
  assert_missing "$SANDBOX_HOME/.cargo/registry/src/index"
  assert_exists "$SANDBOX_HOME/.cargo/registry/index/cache-index"
  assert_exists "$SANDBOX_HOME/.cargo/bin/tool"
  assert_exists "$SANDBOX_HOME/.cargo/git/checkouts/repo/file"
}

@test "docker cleaning is exactly image prune -f" {
  stub_tool docker 'case "$1" in
    images) echo aaa111 ;;
    image) echo "Deleted Images:"; echo "Total reclaimed space: 1.5MB" ;;
  esac'
  scan_for_token
  : > "$STUB_LOG"
  clean_categories docker-dangling
  [ "$(json res docker-dangling status)" = "cleaned" ]
  [ "$(json res docker-dangling freed_bytes)" = "1500000" ]
  grep -qx "docker image prune -f" "$STUB_LOG"
  ! grep -qE "volume|system| -a|--all" "$STUB_LOG"
}

@test "docker daemon stopping after the scan is unavailable" {
  stub_tool docker 'case "$1" in images) echo aaa111 ;; esac'
  scan_for_token
  stub_tool docker 'exit 1'
  clean_categories docker-dangling
  [ "$(json res docker-dangling status)" = "unavailable" ]
  ! grep -q prune "$STUB_LOG"
}

@test "simulator cleaning is exactly simctl delete unavailable" {
  stub_tool xcrun 'case "$*" in
    "simctl list devices unavailable")
      echo "    iPhone 11 (8E7A1B2C-1111-2222-3333-444455556666) (Shutdown) (unavailable)" ;;
  esac'
  scan_for_token
  clean_categories xcode-simulators-unavailable
  [ "$(json res xcode-simulators-unavailable status)" = "cleaned" ]
  grep -qx "xcrun simctl delete unavailable" "$STUB_LOG"
  ! grep -qE "erase|delete all" "$STUB_LOG"
}

@test "device support removes only the stale version folders" {
  local support="$SANDBOX_HOME/Library/Developer/Xcode/iOS DeviceSupport"
  make_file "$support/15.0 (19A346)/Symbols/dyld" 8
  make_file "$support/17.0 (21A329)/Symbols/dyld" 8
  age_tree "$support/15.0 (19A346)" 120
  scan_for_token
  clean_categories xcode-device-support
  [ "$(json res xcode-device-support status)" = "cleaned" ]
  assert_missing "$support/15.0 (19A346)"
  assert_exists "$support/17.0 (21A329)/Symbols/dyld"
}

@test "derived data is emptied while archives stay" {
  local xcode="$SANDBOX_HOME/Library/Developer/Xcode"
  make_file "$xcode/DerivedData/App-abc/Build/object.o" 8
  make_file "$xcode/Archives/2026-01-01/App.xcarchive/Info.plist" 8
  scan_for_token
  clean_categories xcode-derived-data
  [ "$(json res xcode-derived-data status)" = "cleaned" ]
  [ -d "$xcode/DerivedData" ]
  assert_missing "$xcode/DerivedData/App-abc"
  assert_exists "$xcode/Archives/2026-01-01/App.xcarchive/Info.plist"
}

@test "undeletable entries produce partial, not a crash" {
  local cache="$SANDBOX_HOME/Library/Caches/com.example.editor"
  make_file "$cache/free/data.bin" 8
  make_file "$cache/locked/data.bin" 8
  chmod 500 "$cache/locked"
  scan_for_token
  clean_categories app-caches
  [ "$status" -eq 0 ]
  [ "$(json res app-caches status)" = "partial" ]
  [ "$(json res app-caches error_code)" = "SOME_ITEMS_REMAIN" ]
  assert_exists "$cache/locked/data.bin"
  assert_missing "$cache/free"
}

@test "a fully protected category is skipped_no_permission" {
  local cache="$SANDBOX_HOME/Library/Caches/com.example.editor"
  make_file "$cache/locked/data.bin" 8
  chmod 500 "$cache/locked" "$cache"
  scan_for_token
  clean_categories app-caches
  [ "$status" -eq 0 ]
  [ "$(json res app-caches status)" = "skipped_no_permission" ]
  [ "$(json res app-caches freed_bytes)" = "0" ]
  assert_exists "$cache/locked/data.bin"
}

@test "a cache folder replaced by a symlink after the scan is not followed" {
  make_chrome_profile
  make_file "$OUTSIDE/precious/keep.txt" 4
  scan_for_token
  mv "$CHROME_CACHE/Cache" "$SANDBOX/moved-cache"
  ln -s "$OUTSIDE/precious" "$CHROME_CACHE/Cache"
  clean_categories browser-chrome
  [ "$status" -eq 0 ]
  assert_exists "$OUTSIDE/precious/keep.txt"
  assert_exists "$CHROME_CACHE/Cache"
}

@test "a cache folder symlinked outside the home is never emptied" {
  make_file "$OUTSIDE/external-cache/Default/Cache/blob" 8
  mkdir -p "$SANDBOX_HOME/Library/Caches/Google"
  ln -s "$OUTSIDE/external-cache" "$SANDBOX_HOME/Library/Caches/Google/Chrome"
  make_file "$OUTSIDE/gradle-caches/artifact.jar" 8
  mkdir -p "$SANDBOX_HOME/.gradle"
  ln -s "$OUTSIDE/gradle-caches" "$SANDBOX_HOME/.gradle/caches"
  scan_for_token
  [ "$(json cat browser-chrome status)" = "not_found" ]
  [ "$(json cat gradle-cache status)" = "not_found" ]
  assert_exists "$OUTSIDE/external-cache/Default/Cache/blob"
}

@test "--log writes deleted paths to a private local file only" {
  make_chrome_profile
  scan_for_token
  clean_categories browser-chrome --log
  [ "$(json get log_file_written)" = "true" ]
  [ "$(json get log_location_hint)" = "~/Library/Application Support/disk-cleanup/logs" ]
  assert_private blob-one Cache_Data
  local log_file
  log_file=$(find "$STATE_DIR/logs" -type f)
  [ "$(stat -f '%Lp' "$log_file")" = "600" ]
  [ "$(stat -f '%Lp' "$STATE_DIR/logs")" = "700" ]
  grep -q "Cache_Data/blob-one" "$log_file"
}

@test "without --log no log file is written" {
  make_chrome_profile
  scan_for_token
  clean_categories browser-chrome
  [ "$(json get log_file_written)" = "false" ]
  [ "$(json get log_location_hint)" = "null" ]
  [ -z "$(find "$STATE_DIR" -type f)" ]
}
