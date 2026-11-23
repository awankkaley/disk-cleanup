#!/usr/bin/env bats

load helpers/common

setup() {
  setup_sandbox
  SUPPORT="$SANDBOX_HOME/Library/Application Support"
  make_file "$SUPPORT/Slack/Cache/Cache_Data/blob" 64
  make_file "$SUPPORT/Slack/Code Cache/js/blob" 32
  make_file "$SUPPORT/Slack/GPUCache/blob" 16
  make_file "$SUPPORT/Slack/storage/root-state.json" 4
  make_file "$SUPPORT/Slack/IndexedDB/messages.leveldb/000003.log" 4
  make_file "$SUPPORT/Slack/Local Storage/leveldb/000005.ldb" 4
  make_file "$SUPPORT/Slack/Cookies" 4
  make_file "$SUPPORT/Slack/Service Worker/CacheStorage/sw-blob" 4
  make_file "$SUPPORT/discord/Cache/Cache_Data/blob" 64
  make_file "$SUPPORT/discord/settings.json" 4
  make_file "$SUPPORT/Microsoft/Teams/Cache/blob" 32
  make_file "$SUPPORT/Microsoft/Teams/desktop-config.json" 4
  make_file "$SUPPORT/Spotify/PersistentCache/Storage/a1/blob.file" 128
  make_file "$SUPPORT/Spotify/Users/someone-user/prefs" 4
  make_file "$SUPPORT/Spotify/prefs" 4
  make_file "$SUPPORT/Spotify/PersistentCache/Users/someone-user/offline.bnk" 4
  make_file "$SUPPORT/zoom.us/data/zoomus.enc.db" 4
  make_file "$SUPPORT/zoom.us/Cache/blob" 32
  make_file "$SUPPORT/Telegram Desktop/Cache/blob" 32
  make_file "$SUPPORT/WhatsApp/Cache/blob" 32
  make_file "$SUPPORT/WhatsApp/IndexedDB/store.leveldb/000003.log" 4
  make_file "$SUPPORT/Telegram Desktop/tdata/user_data/media_cache/0/blob" 4
  make_file "$SUPPORT/Telegram Desktop/tdata/key_datas" 4
  make_file "$SUPPORT/Code/CachedData/abc123/chrome/js/blob.code" 64
  make_file "$SUPPORT/Code/Cache/Cache_Data/blob" 32
  make_file "$SUPPORT/Code/User/settings.json" 4
  make_file "$SUPPORT/Code/User/globalStorage/state.vscdb" 4
  make_file "$SUPPORT/Code/CachedExtensionVSIXs/some.extension" 4
  make_file "$SUPPORT/Unknown App/Cache/blob" 64
}
teardown() { teardown_sandbox; }

KEPT=(
  "Slack/storage/root-state.json" "Slack/IndexedDB/messages.leveldb/000003.log"
  "Slack/Local Storage/leveldb/000005.ldb" "Slack/Cookies" "Slack/Service Worker/CacheStorage/sw-blob"
  "discord/settings.json" "Microsoft/Teams/desktop-config.json"
  "Spotify/Users/someone-user/prefs" "Spotify/prefs" "zoom.us/data/zoomus.enc.db"
  "Spotify/PersistentCache/Storage/a1/blob.file" "Spotify/PersistentCache/Users/someone-user/offline.bnk"
  "zoom.us/Cache/blob" "WhatsApp/Cache/blob" "Telegram Desktop/Cache/blob"
  "WhatsApp/IndexedDB/store.leveldb/000003.log"
  "Telegram Desktop/tdata/user_data/media_cache/0/blob" "Telegram Desktop/tdata/key_datas"
  "Code/User/settings.json" "Code/User/globalStorage/state.vscdb"
  "Code/CachedExtensionVSIXs/some.extension" "Unknown App/Cache/blob"
)

assert_kept() {
  local path
  for path in "${KEPT[@]}"; do assert_exists "$SUPPORT/$path" || return 1; done
}

@test "app-caches counts the caches of the known chat and editor apps only" {
  run_cleanup scan
  assert_json_schema scan
  [ "$(json cat app-caches status)" = "ok" ]
  [ "$(json cat app-caches item_count)" = "7" ]
  assert_private Slack discord Spotify WhatsApp Telegram
}

@test "cleaning app-caches empties only the cache folders of known apps" {
  scan_for_token
  clean_categories app-caches
  [ "$status" -eq 0 ]
  [ "$(json res app-caches status)" = "cleaned" ]
  assert_missing "$SUPPORT/Slack/Cache/Cache_Data"
  assert_missing "$SUPPORT/Slack/Code Cache/js"
  assert_missing "$SUPPORT/Slack/GPUCache/blob"
  assert_missing "$SUPPORT/discord/Cache/Cache_Data"
  assert_missing "$SUPPORT/Microsoft/Teams/Cache/blob"
  assert_missing "$SUPPORT/Code/CachedData/abc123"
  assert_missing "$SUPPORT/Code/Cache/Cache_Data"
  assert_exists "$SUPPORT/Slack/Cache"
  assert_kept
}

@test "a running known app keeps its caches; the others are still cleaned" {
  mark_app_running "Slack" "com.tinyspeck.slackmacgap"
  mark_app_running "Visual Studio Code" "com.microsoft.VSCode"
  scan_for_token
  [ "$(json cat app-caches item_count)" = "2" ]
  clean_categories app-caches
  [ "$status" -eq 0 ]
  assert_exists "$SUPPORT/Slack/Cache/Cache_Data/blob"
  assert_exists "$SUPPORT/Slack/GPUCache/blob"
  assert_exists "$SUPPORT/Code/CachedData/abc123/chrome/js/blob.code"
  assert_exists "$SUPPORT/Code/Cache/Cache_Data/blob"
  assert_missing "$SUPPORT/discord/Cache/Cache_Data"
  assert_missing "$SUPPORT/Microsoft/Teams/Cache/blob"
  assert_kept
}

@test "Spotify offline downloads and unverified app layouts are never touched" {
  /bin/rm -rf "$SUPPORT/Slack" "$SUPPORT/discord" "$SUPPORT/Microsoft" "$SUPPORT/Code"
  run_cleanup scan
  [ "$(json cat app-caches status)" = "not_found" ]
  local table
  table=$(/usr/bin/sed -n '/^readonly KNOWN_APP_CACHE_ROWS=(/,/^)/p' "$PROJECT_ROOT/scripts/lib/catalog.sh")
  [ "$(printf '%s\n' "$table" | /usr/bin/grep -c '|')" = "4" ]
  run /usr/bin/grep -ciE 'spotify|zoom|whatsapp|telegram|PersistentCache' <<< "$table"
  [ "$output" = "0" ]
}

@test "a cache folder that is a symlink is never followed" {
  make_file "$OUTSIDE/elsewhere/precious.bin" 8
  /bin/rm -rf "$SUPPORT/discord/Cache"
  ln -s "$OUTSIDE/elsewhere" "$SUPPORT/discord/Cache"
  scan_for_token
  clean_categories app-caches
  [ "$status" -eq 0 ]
  assert_exists "$OUTSIDE/elsewhere/precious.bin"
}

@test "cache-named folders deeper inside a known app are left alone" {
  make_file "$SUPPORT/Slack/Partitions/workspace/Cache/blob" 8
  make_file "$SUPPORT/Code/User/workspaceStorage/abc/Cache/blob" 8
  scan_for_token
  clean_categories app-caches
  assert_exists "$SUPPORT/Slack/Partitions/workspace/Cache/blob"
  assert_exists "$SUPPORT/Code/User/workspaceStorage/abc/Cache/blob"
}

@test "ios-updates is a recommended system category" {
  make_file "$SANDBOX_HOME/Library/iTunes/iPhone Software Updates/iPhone_Restore.ipsw" 256
  run_cleanup scan
  assert_json_schema scan
  [ "$(json cat ios-updates status)" = "ok" ]
  [ "$(json cat ios-updates group)" = "system" ]
  [ "$(json cat ios-updates risk)" = "safe" ]
  [ "$(json cat ios-updates recommended)" = "true" ]
  [ "$(json cat ios-updates item_count)" = "1" ]
  assert_private iPhone_Restore ipsw
}

@test "ios-updates is not_found when no update folder exists" {
  run_cleanup scan
  [ "$(json cat ios-updates status)" = "not_found" ]
}

@test "cleaning ios-updates removes installers and never device backups" {
  local itunes="$SANDBOX_HOME/Library/iTunes"
  make_file "$itunes/iPhone Software Updates/iPhone_Restore.ipsw" 256
  make_file "$itunes/iPad Software Updates/iPad_Restore.ipsw" 128
  make_file "$itunes/iPod Software Updates/iPod_Restore.ipsw" 64
  make_file "$itunes/iTunes Library.itl" 8
  make_file "$SANDBOX_HOME/Library/Application Support/MobileSync/Backup/0000-device/Manifest.db" 64
  scan_for_token
  [ "$(json cat ios-updates item_count)" = "3" ]
  clean_categories ios-updates
  [ "$status" -eq 0 ]
  assert_json_schema clean
  [ "$(json res ios-updates status)" = "cleaned" ]
  assert_missing "$itunes/iPhone Software Updates/iPhone_Restore.ipsw"
  assert_missing "$itunes/iPad Software Updates/iPad_Restore.ipsw"
  assert_missing "$itunes/iPod Software Updates/iPod_Restore.ipsw"
  assert_exists "$itunes/iPhone Software Updates"
  assert_exists "$itunes/iTunes Library.itl"
  assert_exists "$SANDBOX_HOME/Library/Application Support/MobileSync/Backup/0000-device/Manifest.db"
}
