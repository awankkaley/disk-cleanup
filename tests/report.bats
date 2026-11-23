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

ROW_PATTERN='^<tr data-id="[0-9]+" data-size="[0-9]+" data-mtime="[0-9]+" data-group="(large-files|old-downloads)"><td class="pick"><input type="checkbox" id="item-[0-9]+"></td><td class="name" dir="auto"><label for="item-[0-9]+">[^<>]*</label></td><td class="folder" dir="auto">[^<>]*</td><td class="size"></td><td class="date"></td><td class="group"></td></tr>$'

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
  report_has "<tbody id=\"rows\" data-token=\"$TOKEN\" data-secret=\"$SECRET\">"
  [ "$(/usr/bin/grep -c '^<tr data-id=' "$REPORT")" = "$(json get total_item_count)" ]
  [ "$(/usr/bin/grep '^<tr data-id=' "$REPORT" | /usr/bin/grep -cvE "$ROW_PATTERN")" = "0" ]
  report_lacks ' checked'
  local size mtime
  size=$((12 * MEBIBYTE))
  mtime=$(/usr/bin/stat -f '%m' "$HOME_DIR/Movies/trip/plain-video.mov")
  report_has "<tr data-id=\"1\" data-size=\"$size\" data-mtime=\"$mtime\" data-group=\"large-files\"><td class=\"pick\"><input type=\"checkbox\" id=\"item-1\"></td><td class=\"name\" dir=\"auto\"><label for=\"item-1\">plain-video.mov</label></td><td class=\"folder\" dir=\"auto\">~/Movies/trip</td>"
  report_has '<label for="item-2">old-form.pdf</label></td><td class="folder" dir="auto">~/Downloads</td>'
}

@test "the home path never appears in the report; folders use a tilde" {
  make_big_file "$HOME_DIR/top-level.iso" 11
  review_for_token
  report_lacks "$HOME_DIR"
  report_lacks "$(id -un)/"
  report_has '<label for="item-1">plain-video.mov</label>'
  report_has '>top-level.iso</label></td><td class="folder" dir="auto">~</td>'
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
  report_has 'a&amp;b &#39;q&#39; &quot;d&quot;.mp4</label></td><td class="folder" dir="auto">~/Documents/&quot;&gt;&lt;svg onload=alert(3)&gt;</td>'
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
  report_has "<tbody id=\"rows\" data-token=\"$TOKEN\" data-secret=\"$SECRET\">"
  [ "$(/usr/bin/grep -c '^<tr data-id=' "$REPORT")" = "0" ]
  report_has '</html>'
}

@test "the page carries the selection secret and writes it into the saved file" {
  review_for_token
  [[ "$SECRET" =~ ^[0-9a-f]{32}$ ]]
  [ "$(/usr/bin/grep -c "$SECRET" "$REPORT")" = "1" ]
  report_has 'getAttribute("data-secret")'
  report_has '/^[0-9a-f]{32}$/.test(secret)'
  report_has '"{\"token\":\"" + token + "\",\"secret\":\"" + secret + "\",\"ids\":[" + ids.join(",") + "]}"'
}

@test "names and folders are isolated against bidirectional text tricks" {
  review_for_token
  report_has 'unicode-bidi: isolate'
  [ "$(/usr/bin/grep -c '<td class="name" dir="auto">' "$REPORT")" = "$(json get total_item_count)" ]
  [ "$(/usr/bin/grep -c '<td class="folder" dir="auto">' "$REPORT")" = "$(json get total_item_count)" ]
}

@test "only the checkbox and its label tick a row" {
  review_for_token
  report_lacks 'closest('
  report_lacks 'tbody tr { cursor: pointer'
  report_lacks '.checked = !'
  [ "$(/usr/bin/grep -c 'addEventListener("click"' "$REPORT")" = "4" ]
}

@test "the summary says how many ticked items the filter hides" {
  review_for_token
  report_has 'hidden by the filter'
  report_has 'tersembunyi oleh filter'
  report_has '{hidden}'
  report_has 'Selesai memilih'
  report_has '>Done choosing</button>'
}

@test "the button is called Done choosing and a plain note above it says where the file goes" {
  review_for_token
  report_lacks 'Save selection'
  report_lacks 'Simpan pilihan'
  report_has 'save: "Done choosing"'
  report_has 'save: "Selesai memilih"'
  report_has 'Pressing the button saves a small file named disk-cleanup-selection.json. If your browser asks where to save it, choose Downloads.'
  report_has 'Tombol ini menyimpan file kecil bernama disk-cleanup-selection.json. Kalau browser bertanya mau disimpan di mana, pilih Downloads.'
  report_has '<p id="save-note" data-i18n="saveNote">Pressing the button'
  report_has '<button type="button" id="save" disabled aria-describedby="save-note" data-i18n="save">Done choosing</button>'
  local note_line button_line
  note_line=$(/usr/bin/grep -n 'id="save-note"' "$REPORT" | /usr/bin/cut -d: -f1)
  button_line=$(/usr/bin/grep -n 'id="save" disabled' "$REPORT" | /usr/bin/cut -d: -f1)
  [ "$button_line" = "$((note_line + 1))" ]
}

@test "after saving, a full-page done screen names the single next step in both languages" {
  review_for_token
  report_has '<section class="done" id="done" hidden aria-labelledby="done-title">'
  report_has '<p class="tick" aria-hidden="true">&#10003;</p>'
  report_has '<h2 id="done-title" tabindex="-1" data-i18n="doneTitle">Your choice is saved</h2>'
  report_has '<p id="done-count"></p>'
  report_has '<p class="next"><span data-i18n="doneNext">Go back to your assistant and type:</span> <strong data-i18n="doneWord">done</strong></p>'
  report_has '<p class="calm" data-i18n="doneCalm">Nothing has been moved yet. You can close this page.</p>'
  report_has '<button type="button" id="change" data-i18n="change">Change my choice</button>'
  report_has 'doneTitle: "Pilihan Anda tersimpan"'
  report_has 'doneNext: "Kembali ke asisten dan ketik:", doneWord: "selesai"'
  report_has 'doneCalm: "Belum ada yang dipindahkan. Halaman ini boleh ditutup."'
  report_has 'change: "Ubah pilihan"'
  report_has 'doneOne: "You chose 1 item, {size} in total."'
  report_has 'doneMany: "You chose {n} items, {size} in total."'
  report_has 'doneOne: "Anda memilih 1 item, total {size}."'
  report_has 'doneMany: "Anda memilih {n} item, total {size}."'
  report_has 'heading.focus()'
  report_has '@media (prefers-reduced-motion: no-preference)'
  report_lacks 'id="saved"'
  [ "$(/usr/bin/grep -c '<script' "$REPORT")" = "1" ]
}
