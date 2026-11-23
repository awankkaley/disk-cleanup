#!/usr/bin/env bats

load helpers/common

bats_require_minimum_version 1.5.0

FIXTURE_NAMES=(holiday-video capybara-archive axolotl-setup tapir-notes pangolin-folder)

setup() {
  setup_sandbox
  HOME_DIR=$SANDBOX_HOME
  make_big_file "$HOME_DIR/Movies/pangolin-folder/holiday-video.mov" 13
  make_big_file "$HOME_DIR/Documents/capybara-archive.zip" 11
  make_big_file "$HOME_DIR/Downloads/axolotl-setup.dmg" 12
  make_file "$HOME_DIR/Downloads/tapir-notes.pdf" 16
  age_path "$HOME_DIR/Downloads/tapir-notes.pdf" 120
  make_file "$HOME_DIR/Downloads/fresh-notes.pdf" 16
  make_file "$HOME_DIR/Documents/small-letter.txt" 16
  age_path "$HOME_DIR/Documents/small-letter.txt" 400
  stub_open
}
teardown() { teardown_sandbox; }

listed() {
  manifest_paths | /usr/bin/grep -Fxq -- "$1" || { echo "not listed: $1"; return 1; }
}

not_listed() {
  if manifest_paths | /usr/bin/grep -Fq -- "$1"; then echo "listed: $1"; return 1; fi
}

@test "review prints one schema-valid document with counts and totals only" {
  review_for_token
  assert_json_schema review
  [ "${#lines[@]}" -eq 1 ]
  [ "$(json get groups.0.item_count)" = "3" ]
  [ "$(json get groups.0.size_bytes)" = "$((36 * MEBIBYTE))" ]
  [ "$(json get groups.1.item_count)" = "1" ]
  [ "$(json get groups.1.size_bytes)" = "16384" ]
  [ "$(json get total_item_count)" = "4" ]
  [ "$(json get truncated)" = "false" ]
  [ "$(json get skipped_no_permission)" = "null" ]
}

@test "review output and errors carry no item names or paths" {
  review_for_token
  assert_private "${FIXTURE_NAMES[@]}" small-letter fresh-notes
  run_cleanup review --min-size-mb "holiday-video"
  assert_error INVALID_ARGUMENT
  assert_private "${FIXTURE_NAMES[@]}"
  run_cleanup review "$HOME_DIR/Documents/capybara-archive.zip"
  assert_error USAGE 2
  assert_private "${FIXTURE_NAMES[@]}"
}

@test "review writes nothing to stderr" {
  run --separate-stderr sandbox_env /bin/bash "$CLEANUP" review --min-size-mb 10
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "the manifest lists id, size, mtime, group and absolute path, largest first" {
  review_for_token
  [ "$(/usr/bin/sed -n 2p "$MANIFEST")" = "token=$TOKEN" ]
  [[ "$(/usr/bin/sed -n 3p "$MANIFEST")" =~ ^epoch=[0-9]+$ ]]
  [ "$(manifest_id "$HOME_DIR/Movies/pangolin-folder/holiday-video.mov")" = "1" ]
  [ "$(manifest_id "$HOME_DIR/Downloads/axolotl-setup.dmg")" = "2" ]
  [ "$(manifest_id "$HOME_DIR/Documents/capybara-archive.zip")" = "3" ]
  [ "$(manifest_id "$HOME_DIR/Downloads/tapir-notes.pdf")" = "4" ]
  local mtime
  mtime=$(/usr/bin/stat -f '%m' "$HOME_DIR/Downloads/tapir-notes.pdf")
  /usr/bin/grep -q "^4	16384	16384	$mtime	old-downloads	$HOME_DIR/Downloads/tapir-notes.pdf\$" "$MANIFEST"
  /usr/bin/grep -q "^2	$((12 * MEBIBYTE))	$((12 * MEBIBYTE))	[0-9]*	large-files	" "$MANIFEST"
}

@test "an item belongs to one group only and large-files wins" {
  age_path "$HOME_DIR/Downloads/axolotl-setup.dmg" 200
  review_for_token
  [ "$(manifest_paths | /usr/bin/grep -c 'axolotl-setup')" = "1" ]
  /usr/bin/grep -q "large-files	$HOME_DIR/Downloads/axolotl-setup.dmg\$" "$MANIFEST"
}

@test "old-downloads covers only old files directly inside Downloads" {
  make_file "$HOME_DIR/Downloads/unpacked/nested-old.bin" 16
  age_tree "$HOME_DIR/Downloads/unpacked" 300
  make_file "$HOME_DIR/Downloads/almost-old.bin" 16
  age_path "$HOME_DIR/Downloads/almost-old.bin" 80
  review_for_token
  listed "$HOME_DIR/Downloads/tapir-notes.pdf"
  not_listed fresh-notes
  not_listed nested-old
  not_listed almost-old
  not_listed small-letter
}

@test "--downloads-age-days changes the age threshold" {
  make_file "$HOME_DIR/Downloads/ten-days.bin" 16
  age_path "$HOME_DIR/Downloads/ten-days.bin" 10
  review_for_token --downloads-age-days 7
  listed "$HOME_DIR/Downloads/ten-days.bin"
  not_listed fresh-notes
}

@test "the default minimum size is 100 MB" {
  run_cleanup review
  [ "$status" -eq 0 ]
  [ "$(json get groups.0.item_count)" = "0" ]
  [ "$(json get groups.1.item_count)" = "1" ]
}

@test "a large file directly in the home directory is listed" {
  make_big_file "$HOME_DIR/installer-image.iso" 11
  review_for_token
  listed "$HOME_DIR/installer-image.iso"
}

@test "pruned locations and bundles are never listed" {
  local pruned
  for pruned in "Library/Containers/app/big.bin" ".hidden-dir/big.bin" "work/node_modules/pkg/big.bin" \
    ".Trash/big.bin" "Applications/Tool.app/Contents/big.bin" "Pictures/Photos Library.photoslibrary/originals/big.heic" \
    "Music/Song.BAND/big.aif" "Movies/Edit.fcpbundle/big.mov" "vm/Disk.sparsebundle/bands/big" \
    "vm/Linux.utm/Data/big.qcow2" "vm/Win.pvm/big.hdd" "vm/Mac.VMwareVM/big.vmdk" "code/App.xcodeproj/big.bin" \
    "Pictures/Catalog.lrdata/big.bin" "Pictures/Catalog.lrcat/big.bin" "Music/Lib.musiclibrary/big.bin" \
    "Movies/TV.tvlibrary/big.bin" "Movies/Old.imovielibrary/big.bin" "Music/Proj.logicx/big.bin" \
    "dev/Thing.framework/big.bin" "dev/Thing.bundle/big.bin" "AppData/Local/big.bin"; do
    make_big_file "$HOME_DIR/$pruned" 11
  done
  make_big_file "$HOME_DIR/Documents/.hidden-big-file" 11
  review_for_token
  [ "$(json get total_item_count)" = "4" ]
  not_listed "big"
  not_listed "hidden-big-file"
}

@test "a folder named Library deeper in the home directory is still reviewed" {
  make_big_file "$HOME_DIR/Documents/Library/sample-pack.wav" 11
  review_for_token
  listed "$HOME_DIR/Documents/Library/sample-pack.wav"
}

@test "symlinks are never listed or followed" {
  make_big_file "$OUTSIDE/far-away/outside-big.bin" 11
  ln -s "$OUTSIDE/far-away" "$HOME_DIR/Documents/linked-folder"
  ln -s "$OUTSIDE/far-away/outside-big.bin" "$HOME_DIR/Documents/linked-file.bin"
  ln -s "$HOME_DIR/Movies/pangolin-folder/holiday-video.mov" "$HOME_DIR/Downloads/alias.mov"
  age_path "$HOME_DIR/Downloads/alias.mov" 200
  review_for_token
  [ "$(json get total_item_count)" = "4" ]
  not_listed "linked-"
  not_listed "alias.mov"
  not_listed "far-away"
}

@test "files without allocated blocks are skipped" {
  make_placeholder_file "$HOME_DIR/Documents/cloud-only-video.mov" 50
  make_placeholder_file "$HOME_DIR/Downloads/cloud-only-old.zip" 1
  age_path "$HOME_DIR/Downloads/cloud-only-old.zip" 200
  [ "$(/usr/bin/stat -f '%b' "$HOME_DIR/Documents/cloud-only-video.mov")" = "0" ]
  review_for_token
  not_listed "cloud-only"
}

@test "names with a tab, newline or other control character are skipped" {
  make_big_file "$HOME_DIR/Documents/tab"$'\t'"name.bin" 11
  make_big_file "$HOME_DIR/Documents/line"$'\n'"break.bin" 11
  make_big_file "$HOME_DIR/Documents/bell"$'\a'"name.bin" 11
  make_big_file "$HOME_DIR/Documents/odd"$'\n'"folder/inner-big.bin" 11
  make_big_file "$HOME_DIR/Documents/Ünïcödé 文件 😀.bin" 11
  review_for_token
  [ "$(json get total_item_count)" = "5" ]
  listed "$HOME_DIR/Documents/Ünïcödé 文件 😀.bin"
  not_listed "name.bin"
  not_listed "inner-big"
}

@test "a crafted name cannot smuggle an extra manifest line" {
  make_big_file "$HOME_DIR/Documents/x"$'\n'"99999 99999 1 .${OUTSIDE}/victim" 11
  review_for_token
  not_listed "victim"
  [ "$(json get total_item_count)" = "4" ]
}

@test "review deletes and moves nothing" {
  local before after
  mkdir -p "$HOME_DIR/Library/Application Support"
  before=$(snapshot_tree)
  review_for_token
  after=$(snapshot_tree)
  [ "$before" = "$after" ]
}

@test "review keeps at most 500 items, largest first, and reports truncation" {
  local index
  for index in $(seq 1 505); do : > "$HOME_DIR/Downloads/tiny-$index.txt"; echo x > "$HOME_DIR/Downloads/tiny-$index.txt"; done
  age_tree "$HOME_DIR/Downloads" 200
  review_for_token
  assert_json_schema review
  [ "$(json get total_item_count)" = "500" ]
  [ "$(json get truncated)" = "true" ]
  [ "$(manifest_paths | /usr/bin/wc -l | /usr/bin/tr -d ' ')" = "500" ]
  [ "$(manifest_id "$HOME_DIR/Movies/pangolin-folder/holiday-video.mov")" = "1" ]
  listed "$HOME_DIR/Downloads/axolotl-setup.dmg"
}

@test "the state dir is private: dir 700, files 600" {
  review_for_token
  [ "$(/usr/bin/stat -f '%Lp' "$STATE_DIR")" = "700" ]
  [ "$(/usr/bin/stat -f '%Lp' "$MANIFEST")" = "600" ]
  [ "$(/usr/bin/stat -f '%Lp' "$REPORT")" = "600" ]
}

@test "the report is opened through the open tool" {
  review_for_token
  [ "$(json get report_opened)" = "true" ]
  /usr/bin/grep -Fxq "open $REPORT" "$STUB_LOG"
}

@test "failure to open the report is not an error" {
  stub_open 'exit 1'
  review_for_token
  [ "$(json get report_opened)" = "false" ]
  /bin/rm "$STUB_BIN/open"
  review_for_token
  assert_json_schema review
  [ "$(json get report_opened)" = "false" ]
  assert_exists "$REPORT"
}

@test "an unreadable folder is skipped and flagged" {
  make_big_file "$HOME_DIR/Private/locked-big.bin" 11
  chmod 000 "$HOME_DIR/Private"
  review_for_token
  assert_json_schema review
  [ "$(json get skipped_no_permission)" = "true" ]
  [ "$(json get total_item_count)" = "4" ]
  [ "${#lines[@]}" -eq 1 ]
  assert_private "${FIXTURE_NAMES[@]}" Private locked-big
}

@test "every group reports status ok and Downloads is readable" {
  review_for_token
  assert_json_schema review
  [ "$(json get downloads_readable)" = "true" ]
  [ "$(json get groups.0.status)" = "ok" ]
  [ "$(json get groups.1.status)" = "ok" ]
}

@test "a Downloads folder that cannot be listed is reported before the user starts ticking" {
  chmod 000 "$HOME_DIR/Downloads"
  review_for_token
  assert_json_schema review
  [ "$(json get downloads_readable)" = "false" ]
  [ "$(json get skipped_no_permission)" = "true" ]
  [ "$(json get groups.0.status)" = "ok" ]
  [ "$(json get groups.1.status)" = "skipped_no_permission" ]
  [ "$(json get groups.1.item_count)" = "0" ]
  [ "$(json get total_item_count)" = "2" ]
}

@test "no Downloads folder reports downloads_readable null" {
  /bin/rm -rf "$HOME_DIR/Downloads"
  review_for_token
  assert_json_schema review
  [ "$(json get downloads_readable)" = "null" ]
  [ "$(json get groups.1.status)" = "ok" ]
  [ "$(json get groups.1.item_count)" = "0" ]
}

@test "size and age options are validated" {
  local bad
  for bad in 9 0 abc -5 1.5 "" 99999999; do
    run_cleanup review --min-size-mb "$bad"
    assert_error INVALID_ARGUMENT
  done
  for bad in 6 0 soon 36501; do
    run_cleanup review --downloads-age-days "$bad"
    assert_error INVALID_ARGUMENT
  done
  run_cleanup review --min-size-mb
  assert_error USAGE 2
  run_cleanup review --deep
  assert_error USAGE 2
  assert_missing "$STATE_DIR/review-manifest"
}

@test "a review and a scan do not invalidate each other" {
  make_chrome_profile
  scan_for_token
  local scan_token=$TOKEN
  review_for_token
  assert_exists "$STATE_DIR/state"
  run_cleanup clean --token "$scan_token" --categories browser-chrome
  [ "$status" -eq 0 ]
  [ "$(json res browser-chrome status)" = "cleaned" ]
  assert_exists "$MANIFEST"
  run_cleanup scan
  [ "$status" -eq 0 ]
  /usr/bin/grep -q "^token=$TOKEN\$" "$MANIFEST"
}

@test "a new review replaces the previous manifest and token" {
  review_for_token
  local first=$TOKEN
  review_for_token
  [ "$first" != "$TOKEN" ]
  [ "$(/usr/bin/grep -c '^token=' "$MANIFEST")" = "1" ]
  write_selection "$first" 1
  apply_review "$first"
  assert_error TOKEN_INVALID
  assert_exists "$HOME_DIR/Movies/pangolin-folder/holiday-video.mov"
}

@test "review never writes through a planted symlink" {
  mkdir -p "$STATE_DIR"
  echo keep > "$OUTSIDE/victim-file"
  ln -s "$OUTSIDE/victim-file" "$STATE_DIR/review-manifest"
  run_review
  assert_error INTERNAL
  [ "$(/bin/cat "$OUTSIDE/victim-file")" = "keep" ]
  /bin/rm "$STATE_DIR/review-manifest"
  ln -s "$OUTSIDE/victim-file" "$STATE_DIR/review.html"
  run_review
  assert_error INTERNAL
  [ "$(/bin/cat "$OUTSIDE/victim-file")" = "keep" ]
}

@test "the review walks the home directory with a single find and never hashes files" {
  local review_code="$PROJECT_ROOT/scripts/lib/review.sh"
  [ "$(/usr/bin/grep -cE '(^|[^[:alnum:]_])find -P' "$review_code")" -eq 1 ]
  run /usr/bin/grep -nE '(^|[^[:alnum:]_])(md5|cksum|openssl|sha256sum)([^[:alnum:]_]|$)' \
    "$PROJECT_ROOT"/scripts/cleanup.sh "$PROJECT_ROOT"/scripts/lib/*.sh
  [ -z "$output" ]
  # The one hash call seals the manifest; it reads standard input only.
  [ "$(/usr/bin/grep -hvE '^[[:space:]]*#' "$PROJECT_ROOT"/scripts/cleanup.sh "$PROJECT_ROOT"/scripts/lib/*.sh |
    /usr/bin/grep -cE '(^|[^[:alnum:]_])shasum([^[:alnum:]_]|$)')" -eq 1 ]
  /usr/bin/grep -qE '\| shasum -a 256( 2> /dev/null)?\)?$' "$review_code"
}

@test "the manifest header records the secret, the review options and an integrity line" {
  review_for_token --downloads-age-days 30
  [ "$(/usr/bin/sed -n 1p "$MANIFEST")" = "format=2" ]
  [ "$(/usr/bin/sed -n 2p "$MANIFEST")" = "token=$TOKEN" ]
  [[ "$(/usr/bin/sed -n 3p "$MANIFEST")" =~ ^epoch=[0-9]+$ ]]
  [[ "$(/usr/bin/sed -n 4p "$MANIFEST")" =~ ^secret=[0-9a-f]{32}$ ]]
  [ "$(/usr/bin/sed -n 5p "$MANIFEST")" = "min_size_mb=10" ]
  [ "$(/usr/bin/sed -n 6p "$MANIFEST")" = "downloads_age_days=30" ]
  [[ "$(/usr/bin/sed -n 7p "$MANIFEST")" =~ ^integrity=[0-9a-f]{64}$ ]]
  [[ "$(/usr/bin/sed -n 8p "$MANIFEST")" == "1	"* ]]
  local sealed=$(manifest_value integrity)
  reseal_manifest
  [ "$(manifest_value integrity)" = "$sealed" ]
}

@test "the selection secret never reaches stdout or stderr" {
  run --separate-stderr sandbox_env /bin/bash "$CLEANUP" review --min-size-mb 10
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  local secret
  secret=$(/usr/bin/sed -n 's/^secret=//p' "$STATE_DIR/review-manifest")
  [ "${#secret}" -eq 32 ]
  [[ "$output" != *"$secret"* ]]
  [[ "$output" != *"secret"* ]]
  run /usr/bin/grep -cE '[0-9a-f]{9,}' <<< "$output"
  [ "$output" = "0" ]
}

@test "every review gets a fresh secret" {
  review_for_token
  local first=$SECRET
  review_for_token
  [ "$first" != "$SECRET" ]
  [ "$SECRET" != "$TOKEN$TOKEN$TOKEN$TOKEN" ]
}

@test "names with bidirectional control characters are left out of the review" {
  local mark
  for mark in $'\xe2\x80\xaa' $'\xe2\x80\xab' $'\xe2\x80\xac' $'\xe2\x80\xad' $'\xe2\x80\xae' \
    $'\xe2\x81\xa6' $'\xe2\x81\xa7' $'\xe2\x81\xa8' $'\xe2\x81\xa9' $'\xe2\x80\x8e' $'\xe2\x80\x8f' $'\xd8\x9c'; do
    make_big_file "$HOME_DIR/Documents/spoof-${mark}gpj.exe" 11
  done
  make_big_file "$HOME_DIR/Documents/folder-"$'\xe2\x80\xae'"-spoof/inner-big.bin" 11
  make_file "$HOME_DIR/Downloads/old-"$'\xe2\x80\xae'"-spoof.pdf" 16
  age_path "$HOME_DIR/Downloads/old-"$'\xe2\x80\xae'"-spoof.pdf" 200
  make_big_file "$HOME_DIR/Documents/عربي עברית 文件 é—.bin" 11
  review_for_token
  [ "$(json get total_item_count)" = "5" ]
  listed "$HOME_DIR/Documents/عربي עברית 文件 é—.bin"
  not_listed "spoof"
  not_listed "inner-big"
  run /usr/bin/grep -c 'spoof' "$REPORT"
  [ "$output" = "0" ]
}
