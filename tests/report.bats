#!/usr/bin/env bats

load helpers/common

setup() {
  setup_sandbox
  HOME_DIR=$SANDBOX_HOME
  make_big_file "$HOME_DIR/Movies/trip/plain-video.mov" 12
  make_file "$HOME_DIR/Downloads/old-form.pdf" 16
  age_path "$HOME_DIR/Downloads/old-form.pdf" 120
  stub_open
}
teardown() { teardown_sandbox; }

report_has() {
  /usr/bin/grep -Fq -- "$1" "$REPORT" || { echo "report lacks: $1"; return 1; }
}

report_lacks() {
  if /usr/bin/grep -Fq -- "$1" "$REPORT"; then echo "report contains: $1"; return 1; fi
}

ROW_PATTERN='^<tr data-id="[0-9]+" data-size="[0-9]+" data-mtime="[0-9]+" data-group="(large-files|old-downloads)"><td class="pick"><input type="checkbox" id="item-[0-9]+"></td><td class="name"><label for="item-[0-9]+">[^<>]*</label></td><td class="folder">[^<>]*</td><td class="size"></td><td class="date"></td><td class="group"></td></tr>$'

@test "the report is one self-contained page with the required CSP" {
  review_for_token
  report_has "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'\">"
  report_has '<meta charset="utf-8">'
  report_lacks 'http://'
  report_lacks 'https://'
  report_lacks '//cdn'
  report_lacks '@import'
  report_lacks 'url('
  report_lacks ' src='
  report_lacks '<link'
  report_lacks '<iframe'
  [ "$(/usr/bin/grep -c '<script' "$REPORT")" = "1" ]
}

@test "the page carries the token and one row per item, all unchecked" {
  review_for_token
  report_has "<tbody id=\"rows\" data-token=\"$TOKEN\">"
  [ "$(/usr/bin/grep -c '^<tr data-id=' "$REPORT")" = "$(json get total_item_count)" ]
  [ "$(/usr/bin/grep '^<tr data-id=' "$REPORT" | /usr/bin/grep -cvE "$ROW_PATTERN")" = "0" ]
  report_lacks ' checked'
  local size mtime
  size=$((12 * MEBIBYTE))
  mtime=$(/usr/bin/stat -f '%m' "$HOME_DIR/Movies/trip/plain-video.mov")
  report_has "<tr data-id=\"1\" data-size=\"$size\" data-mtime=\"$mtime\" data-group=\"large-files\"><td class=\"pick\"><input type=\"checkbox\" id=\"item-1\"></td><td class=\"name\"><label for=\"item-1\">plain-video.mov</label></td><td class=\"folder\">~/Movies/trip</td>"
  report_has '<label for="item-2">old-form.pdf</label></td><td class="folder">~/Downloads</td>'
}

@test "the home path never appears in the report; folders use a tilde" {
  make_big_file "$HOME_DIR/top-level.iso" 11
  review_for_token
  report_lacks "$HOME_DIR"
  report_lacks "$(id -un)/"
  report_has '<label for="item-1">plain-video.mov</label>'
  report_has '>top-level.iso</label></td><td class="folder">~</td>'
}

@test "hostile file and folder names are rendered as text" {
  make_big_file "$HOME_DIR/Documents/<img src=x onerror=alert(1)>.mov" 11
  make_big_file "$HOME_DIR/Documents/<script>alert(2)<!--.bin" 11
  make_big_file "$HOME_DIR/Documents/\"><svg onload=alert(3)>/a&b 'q' \"d\".mp4" 11
  make_big_file "$HOME_DIR/Documents/\$(touch pwned-by-report) \`touch pwned-too\`.bin" 11
  make_big_file "$HOME_DIR/Documents/&lt;already&amp;escaped&gt;.bin" 11
  make_big_file "$HOME_DIR/Documents/'-alert(4)-'\\.bin" 11
  review_for_token
  [ "$(json get total_item_count)" = "8" ]
  report_lacks '<img'
  report_lacks '<svg'
  report_lacks 'onerror=alert(1)>'
  [ "$(/usr/bin/grep -c '<script' "$REPORT")" = "1" ]
  [ "$(/usr/bin/grep -c '</script' "$REPORT")" = "1" ]
  report_has '&lt;img src=x onerror=alert(1)&gt;.mov</label>'
  report_has '&lt;script&gt;alert(2)&lt;!--.bin</label>'
  report_has 'a&amp;b &#39;q&#39; &quot;d&quot;.mp4</label></td><td class="folder">~/Documents/&quot;&gt;&lt;svg onload=alert(3)&gt;</td>'
  report_has '$(touch pwned-by-report) `touch pwned-too`.bin</label>'
  report_has '&amp;lt;already&amp;amp;escaped&amp;gt;.bin</label>'
  report_has '&#39;-alert(4)-&#39;\.bin</label>'
  [ "$(/usr/bin/grep '^<tr data-id=' "$REPORT" | /usr/bin/grep -cvE "$ROW_PATTERN")" = "0" ]
  [ "$(/usr/bin/grep -c '^<tr data-id=' "$REPORT")" = "8" ]
  assert_missing "$HOME_DIR/pwned-by-report"
  assert_missing "$STATE_DIR/pwned-by-report"
  assert_missing "$HOME_DIR/pwned-too"
}

@test "item data never lands inside the script block" {
  make_big_file "$HOME_DIR/Documents/marker-name-zzz.bin" 11
  review_for_token
  local script_line name_line
  script_line=$(/usr/bin/grep -n '<script' "$REPORT" | /usr/bin/cut -d: -f1)
  name_line=$(/usr/bin/grep -n 'marker-name-zzz' "$REPORT" | /usr/bin/cut -d: -f1)
  [ "$name_line" -lt "$script_line" ]
  [ "$(/usr/bin/grep -c 'marker-name-zzz' "$REPORT")" = "1" ]
}

@test "very long names stay on one valid row" {
  local long
  long=$(printf 'n%.0s' $(seq 1 240))
  make_big_file "$HOME_DIR/Documents/$long.bin" 11
  review_for_token
  report_has ">$long.bin</label>"
  [ "$(/usr/bin/grep '^<tr data-id=' "$REPORT" | /usr/bin/grep -cvE "$ROW_PATTERN")" = "0" ]
}

@test "the page explains the flow and saves the selection under the fixed name" {
  review_for_token
  report_has 'Nothing is deleted from this page'
  report_has 'iCloud, OneDrive or Dropbox'
  report_has 'Tidak ada yang dihapus dari halaman ini'
  report_has 'navigator.language'
  report_has 'disk-cleanup-selection.json'
  report_has 'new Blob('
  report_has '<button type="button" id="save" disabled'
  report_has 'prefers-color-scheme: dark'
  report_has 'aria-live="polite"'
}

@test "a review with nothing to show still writes a valid page" {
  /bin/rm -rf "$HOME_DIR/Movies" "$HOME_DIR/Downloads"
  review_for_token
  [ "$(json get total_item_count)" = "0" ]
  report_has "<tbody id=\"rows\" data-token=\"$TOKEN\">"
  [ "$(/usr/bin/grep -c '^<tr data-id=' "$REPORT")" = "0" ]
  report_has '</html>'
}
