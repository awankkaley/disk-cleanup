#!/usr/bin/env bats

load helpers/common

bats_require_minimum_version 1.5.0

setup() {
  setup_sandbox
  HOME_DIR=$SANDBOX_HOME
  TRASH="$HOME_DIR/.Trash"
  VIDEO="$HOME_DIR/Movies/trip/walrus-video.mov"
  ARCHIVE="$HOME_DIR/Documents/ocelot-archive.zip"
  IMAGE="$HOME_DIR/Downloads/lemur-image.dmg"
  OLD_FORM="$HOME_DIR/Downloads/ibis-form.pdf"
  make_big_file "$VIDEO" 13
  make_big_file "$ARCHIVE" 12
  make_big_file "$IMAGE" 11
  make_file "$OLD_FORM" 16
  age_path "$OLD_FORM" 120
  make_file "$HOME_DIR/Downloads/unrelated-fresh.txt" 4
  stub_open
  review_for_token
  VIDEO_ID=$(manifest_id "$VIDEO")
  ARCHIVE_ID=$(manifest_id "$ARCHIVE")
  IMAGE_ID=$(manifest_id "$IMAGE")
  FORM_ID=$(manifest_id "$OLD_FORM")
}
teardown() { teardown_sandbox; }

SELECTION_NAME="disk-cleanup-selection.json"

count() { json get "$1"; }

# Rewrites the manifest line of ID so that it points at PATH with PATH's facts.
repoint_manifest() {
  local id=$1 path=$2 blocks logical mtime
  blocks=$(/usr/bin/stat -f '%b' "$path")
  logical=$(/usr/bin/stat -f '%z' "$path")
  mtime=$(/usr/bin/stat -f '%m' "$path")
  NEW_LINE="$id	$((blocks * 512))	$logical	$mtime	large-files	$path" WANTED_ID=$id \
    /usr/bin/awk -F '\t' '$1 == ENVIRON["WANTED_ID"] && NF == 6 { print ENVIRON["NEW_LINE"]; next } { print }' \
    "$MANIFEST" > "$SANDBOX/manifest.new"
  /bin/cat "$SANDBOX/manifest.new" > "$MANIFEST"
  reseal_manifest
}

@test "only ticked items are moved to the Trash, intact" {
  write_selection "$TOKEN" "$VIDEO_ID,$FORM_ID"
  apply_review
  [ "$status" -eq 0 ]
  assert_json_schema review-apply
  [ "${#lines[@]}" -eq 1 ]
  [ "$(count selected_count)" = "2" ]
  [ "$(count trashed_count)" = "2" ]
  [ "$(count trashed_bytes)" = "$((13 * MEBIBYTE + 16384))" ]
  assert_missing "$VIDEO"
  assert_missing "$OLD_FORM"
  trash_holds "walrus-video.mov"
  trash_holds "ibis-form.pdf"
  [ "$(/usr/bin/stat -f '%z' "$TRASH/walrus-video.mov")" = "$((13 * MEBIBYTE))" ]
  assert_exists "$ARCHIVE"
  assert_exists "$IMAGE"
  assert_exists "$HOME_DIR/Downloads/unrelated-fresh.txt"
  assert_private walrus-video ibis-form ocelot-archive lemur-image trip
}

@test "Finder is preferred and gets the path as an argument, never as script text" {
  install_finder_stub
  write_selection "$TOKEN" "$VIDEO_ID"
  apply_review
  [ "$(count trashed_count)" = "1" ]
  trash_holds "walrus-video.mov"
  local call
  call=$(/usr/bin/grep '^osascript ' "$STUB_LOG")
  [ "$(printf '%s\n' "$call" | /usr/bin/wc -l | /usr/bin/tr -d ' ')" = "1" ]
  [[ "$call" == *" $VIDEO" ]]
  [ "$(printf '%s' "$call" | /usr/bin/grep -o 'walrus-video' | /usr/bin/wc -l | /usr/bin/tr -d ' ')" = "1" ]
  [[ "$call" == *'item 1 of argv'* ]]
}

@test "a hostile name cannot inject AppleScript or shell code" {
  local evil="$HOME_DIR/Documents/x\" & (do shell script \"touch marker-one\") & \".bin"
  local sneaky="$HOME_DIR/Documents/\$(touch marker-two) \`touch marker-three\`; touch marker-four #.bin"
  local dashed="$HOME_DIR/Documents/-rf"
  make_big_file "$evil" 11
  make_big_file "$sneaky" 11
  make_big_file "$dashed" 11
  install_finder_stub
  review_for_token
  write_selection "$TOKEN" "$(manifest_id "$evil"),$(manifest_id "$sneaky"),$(manifest_id "$dashed")"
  apply_review
  [ "$(count trashed_count)" = "3" ]
  assert_missing "$evil"
  assert_missing "$sneaky"
  assert_missing "$dashed"
  trash_holds "-rf"
  trash_holds "x\" & (do shell script \"touch marker-one\") & \".bin"
  [ -z "$(/usr/bin/find "$SANDBOX" "$PROJECT_ROOT" \( -name marker-one -o -name marker-two -o -name marker-three -o -name marker-four \))" ]
  assert_exists "$VIDEO"
  assert_private marker-one marker-two
}

@test "hostile names are trashed without Finder as well" {
  local sneaky="$HOME_DIR/Documents/\$(touch marker-two) \`touch marker-three\`; 'q' #.bin"
  local dashed="$HOME_DIR/Documents/--help"
  local unicode="$HOME_DIR/Documents/Ünïcödé 文件 😀.bin"
  make_big_file "$sneaky" 11
  make_big_file "$dashed" 11
  make_big_file "$unicode" 11
  review_for_token
  write_selection "$TOKEN" "$(manifest_id "$sneaky"),$(manifest_id "$dashed"),$(manifest_id "$unicode")"
  apply_review
  [ "$(count trashed_count)" = "3" ]
  trash_holds "--help"
  trash_holds "Ünïcödé 文件 😀.bin"
  [ -z "$(/usr/bin/find "$SANDBOX" "$PROJECT_ROOT" \( -name marker-one -o -name marker-two -o -name marker-three -o -name marker-four \))" ]
}

@test "when Finder refuses, the file is moved into the Trash directly" {
  stub_tool osascript 'exit 1'
  write_selection "$TOKEN" "$ARCHIVE_ID"
  apply_review
  [ "$(count trashed_count)" = "1" ]
  [ "$(count failed_count)" = "0" ]
  assert_missing "$ARCHIVE"
  trash_holds "ocelot-archive.zip"
  /usr/bin/grep -q '^osascript ' "$STUB_LOG"
}

@test "a missing Trash folder is created for the direct move" {
  assert_missing "$TRASH"
  write_selection "$TOKEN" "$ARCHIVE_ID"
  apply_review
  [ "$(count trashed_count)" = "1" ]
  trash_holds "ocelot-archive.zip"
}

@test "a file with the same name already in the Trash is never overwritten" {
  mkdir -p "$TRASH"
  echo "earlier one" > "$TRASH/ocelot-archive.zip"
  echo "earlier two" > "$TRASH/ocelot-archive 2.zip"
  write_selection "$TOKEN" "$ARCHIVE_ID"
  apply_review
  [ "$(count trashed_count)" = "1" ]
  assert_missing "$ARCHIVE"
  [ "$(/bin/cat "$TRASH/ocelot-archive.zip")" = "earlier one" ]
  [ "$(/bin/cat "$TRASH/ocelot-archive 2.zip")" = "earlier two" ]
  [ "$(/usr/bin/stat -f '%z' "$TRASH/ocelot-archive 3.zip")" = "$((12 * MEBIBYTE))" ]
}

@test "a very long name that collides in the Trash still gets a unique name" {
  local long
  long="$(printf 'é%.0s' $(seq 1 124)).bin"
  make_big_file "$HOME_DIR/Documents/$long" 11
  mkdir -p "$TRASH"
  echo "earlier" > "$TRASH/$long"
  review_for_token
  write_selection "$TOKEN" "$(manifest_id "$HOME_DIR/Documents/$long")"
  apply_review
  [ "$(count trashed_count)" = "1" ]
  assert_missing "$HOME_DIR/Documents/$long"
  [ "$(/bin/cat "$TRASH/$long")" = "earlier" ]
  [ "$(/usr/bin/find "$TRASH" -type f -size +10M | /usr/bin/wc -l | /usr/bin/tr -d ' ')" = "1" ]
}

@test "unknown ids are ignored and duplicates count once" {
  write_selection "$TOKEN" "$VIDEO_ID,$VIDEO_ID,977,0,123456789012345678901234567890"
  apply_review
  assert_json_schema review-apply
  [ "$(count selected_count)" = "4" ]
  [ "$(count trashed_count)" = "1" ]
  [ "$(count ignored_count)" = "3" ]
  trash_holds "walrus-video.mov"
  assert_exists "$ARCHIVE"
}

@test "an empty selection trashes nothing and discards the review state" {
  write_selection "$TOKEN" ""
  apply_review
  assert_json_schema review-apply
  [ "$(count selected_count)" = "0" ]
  [ "$(count trashed_count)" = "0" ]
  assert_exists "$VIDEO"
  assert_missing "$MANIFEST"
  assert_missing "$REPORT"
  assert_missing "$HOME_DIR/Downloads/$SELECTION_NAME"
}

@test "a file whose size changed is skipped" {
  /usr/bin/touch -r "$ARCHIVE" "$SANDBOX/time-reference"
  echo "appended" >> "$ARCHIVE"
  /usr/bin/touch -r "$SANDBOX/time-reference" "$ARCHIVE"
  write_selection "$TOKEN" "$ARCHIVE_ID,$VIDEO_ID"
  apply_review
  [ "$(count skipped_changed_count)" = "1" ]
  [ "$(count trashed_count)" = "1" ]
  assert_exists "$ARCHIVE"
  assert_missing "$TRASH/ocelot-archive.zip"
}

@test "a file whose modification time changed is skipped" {
  age_path "$ARCHIVE" 3
  write_selection "$TOKEN" "$ARCHIVE_ID"
  apply_review
  [ "$(count skipped_changed_count)" = "1" ]
  [ "$(count trashed_count)" = "0" ]
  assert_exists "$ARCHIVE"
}

@test "a file that disappeared is skipped" {
  /bin/rm "$ARCHIVE"
  write_selection "$TOKEN" "$ARCHIVE_ID"
  apply_review
  [ "$(count skipped_changed_count)" = "1" ]
}

@test "a file swapped for a symlink is skipped and its target untouched" {
  install_finder_stub
  make_big_file "$OUTSIDE/precious.zip" 12
  /usr/bin/touch -r "$ARCHIVE" "$OUTSIDE/precious.zip"
  /bin/rm "$ARCHIVE"
  ln -s "$OUTSIDE/precious.zip" "$ARCHIVE"
  write_selection "$TOKEN" "$ARCHIVE_ID"
  apply_review
  [ "$(count skipped_changed_count)" = "1" ]
  [ "$(count trashed_count)" = "0" ]
  assert_exists "$OUTSIDE/precious.zip"
  assert_exists "$ARCHIVE"
  assert_missing "$TRASH/ocelot-archive.zip"
  run /usr/bin/grep -c '^osascript ' "$STUB_LOG"
  [ "$output" = "0" ]
}

@test "a parent folder swapped for a symlink is skipped" {
  install_finder_stub
  mkdir -p "$OUTSIDE/decoy"
  /bin/cp -p "$VIDEO" "$OUTSIDE/decoy/walrus-video.mov"
  /bin/mv "$HOME_DIR/Movies/trip" "$HOME_DIR/Movies/trip-moved"
  ln -s "$OUTSIDE/decoy" "$HOME_DIR/Movies/trip"
  write_selection "$TOKEN" "$VIDEO_ID"
  apply_review
  [ "$(count skipped_changed_count)" = "1" ]
  [ "$(count trashed_count)" = "0" ]
  assert_exists "$OUTSIDE/decoy/walrus-video.mov"
  assert_exists "$HOME_DIR/Movies/trip-moved/walrus-video.mov"
}

@test "a parent swapped for a symlink to another folder inside home is skipped too" {
  mkdir -p "$HOME_DIR/Pictures/keep"
  /bin/cp -p "$VIDEO" "$HOME_DIR/Pictures/keep/walrus-video.mov"
  /bin/mv "$HOME_DIR/Movies/trip" "$HOME_DIR/Movies/trip-moved"
  ln -s "$HOME_DIR/Pictures/keep" "$HOME_DIR/Movies/trip"
  write_selection "$TOKEN" "$VIDEO_ID"
  apply_review
  [ "$(count skipped_changed_count)" = "1" ]
  assert_exists "$HOME_DIR/Pictures/keep/walrus-video.mov"
}

@test "a manifest path edited to point outside home is refused" {
  make_big_file "$OUTSIDE/outside-victim.bin" 11
  repoint_manifest "$ARCHIVE_ID" "$OUTSIDE/outside-victim.bin"
  write_selection "$TOKEN" "$ARCHIVE_ID"
  apply_review
  [ "$(count skipped_changed_count)" = "1" ]
  [ "$(count trashed_count)" = "0" ]
  assert_exists "$OUTSIDE/outside-victim.bin"
  assert_exists "$ARCHIVE"
}

@test "a manifest path edited to point into a pruned location is refused" {
  local victim victims=(
    "Library/Application Support/SomeApp/database.sqlite" ".ssh/private-key" ".Trash/already.bin"
    "Applications/Tool.app/Contents/MacOS/tool" "Pictures/Photos Library.photoslibrary/database/Photos.sqlite"
    "work/node_modules/pkg/index.js" "library/lowercase.bin" "Music/Song.BAND/audio.aif"
    "Documents/.hidden-file"
  )
  for victim in "${victims[@]}"; do make_big_file "$HOME_DIR/$victim" 11; done
  local id=1 ids=""
  for victim in "${victims[@]}"; do
    printf '%s\t1\t1\t1\tlarge-files\t%s\n' "$((id + 100))" "$HOME_DIR/$victim" >> "$MANIFEST"
    repoint_manifest "$((id + 100))" "$HOME_DIR/$victim"
    ids="$ids${ids:+,}$((id + 100))"
    id=$((id + 1))
  done
  write_selection "$TOKEN" "$ids"
  apply_review
  assert_json_schema review-apply
  [ "$(count selected_count)" = "${#victims[@]}" ]
  [ "$(count skipped_changed_count)" = "${#victims[@]}" ]
  [ "$(count trashed_count)" = "0" ]
  for victim in "${victims[@]}"; do assert_exists "$HOME_DIR/$victim"; done
}

@test "manifest paths with traversal, relative form or the home itself are refused" {
  make_big_file "$HOME_DIR/Library/secret.db" 11
  local facts="$((11 * MEBIBYTE))	$((11 * MEBIBYTE))	$(/usr/bin/stat -f '%m' "$HOME_DIR/Library/secret.db")	large-files"
  {
    printf '201\t%s\t%s\n' "$facts" "$HOME_DIR/Documents/../Library/secret.db"
    printf '202\t%s\t%s\n' "$facts" "Library/secret.db"
    printf '203\t%s\t%s\n' "$facts" "$HOME_DIR"
    printf '204\t%s\t%s\n' "$facts" "$HOME_DIR/Documents//../Library/secret.db"
    printf '205\t%s\t%s\n' "$facts" "$HOME_DIR/./Library/secret.db"
    printf '206\t%s\t%s\n' "$facts" "/"
  } >> "$MANIFEST"
  reseal_manifest
  write_selection "$TOKEN" "201,202,203,204,205,206"
  apply_review
  [ "$(count skipped_changed_count)" = "6" ]
  [ "$(count trashed_count)" = "0" ]
  assert_exists "$HOME_DIR/Library/secret.db"
}

@test "a directory in the manifest is never trashed" {
  mkdir -p "$HOME_DIR/Documents/whole-folder"
  make_big_file "$HOME_DIR/Documents/whole-folder/inside.bin" 11
  repoint_manifest "$ARCHIVE_ID" "$HOME_DIR/Documents/whole-folder"
  write_selection "$TOKEN" "$ARCHIVE_ID"
  apply_review
  [ "$(count skipped_changed_count)" = "1" ]
  assert_exists "$HOME_DIR/Documents/whole-folder/inside.bin"
}

@test "a tampered manifest header invalidates the token" {
  /usr/bin/sed -i '' 's/^epoch=.*/epoch=soon/' "$MANIFEST"
  write_selection "$TOKEN" "$VIDEO_ID"
  apply_review
  assert_error TOKEN_INVALID
  assert_exists "$VIDEO"
}

@test "a symlinked manifest is not trusted" {
  /bin/mv "$MANIFEST" "$OUTSIDE/manifest-copy"
  ln -s "$OUTSIDE/manifest-copy" "$MANIFEST"
  write_selection "$TOKEN" "$VIDEO_ID"
  apply_review
  assert_error TOKEN_INVALID
  assert_exists "$VIDEO"
  assert_exists "$OUTSIDE/manifest-copy"
}

@test "review-apply without a token, before a review, or with a wrong token" {
  write_selection "$TOKEN" "$VIDEO_ID"
  run_cleanup review-apply
  assert_error TOKEN_MISSING
  apply_review 00000000
  assert_error TOKEN_INVALID
  apply_review "walrus-video"
  assert_error TOKEN_INVALID
  assert_private walrus-video
  run_cleanup review-apply --token
  assert_error USAGE 2
  run_cleanup review-apply --token "$TOKEN" --categories trash
  assert_error USAGE 2
  assert_exists "$VIDEO"
  /bin/rm "$MANIFEST"
  apply_review
  assert_error TOKEN_INVALID
  assert_exists "$VIDEO"
}

@test "a scan token is not a review token" {
  scan_for_token
  write_selection "$TOKEN" "$VIDEO_ID"
  apply_review
  assert_error TOKEN_INVALID
  assert_exists "$VIDEO"
}

@test "a review token older than 60 minutes is expired" {
  /usr/bin/sed -i '' "s/^epoch=.*/epoch=$(($(date +%s) - 3601))/" "$MANIFEST"
  write_selection "$TOKEN" "$VIDEO_ID"
  apply_review
  assert_error TOKEN_EXPIRED
  [[ "$output" == *"60 minutes"* ]]
  assert_exists "$VIDEO"
  assert_missing "$MANIFEST"
  assert_missing "$REPORT"
}

@test "a review token just inside the 60 minute window still works" {
  /usr/bin/sed -i '' "s/^epoch=.*/epoch=$(($(date +%s) - 3500))/" "$MANIFEST"
  write_selection "$TOKEN" "$VIDEO_ID"
  apply_review
  [ "$(count trashed_count)" = "1" ]
}

@test "a manifest dated in the future is invalid" {
  /usr/bin/sed -i '' "s/^epoch=.*/epoch=$(($(date +%s) + 5000))/" "$MANIFEST"
  write_selection "$TOKEN" "$VIDEO_ID"
  apply_review
  assert_error TOKEN_INVALID
  assert_exists "$VIDEO"
}

@test "the review token is single-use and the tool's own files are removed" {
  write_selection "$TOKEN" "$VIDEO_ID"
  write_selection "$TOKEN" "$VIDEO_ID" "disk-cleanup-selection (1).json"
  write_selection "deadbeef" "1" "disk-cleanup-selection-7.json"
  apply_review
  [ "$status" -eq 0 ]
  assert_missing "$MANIFEST"
  assert_missing "$REPORT"
  assert_missing "$HOME_DIR/Downloads/$SELECTION_NAME"
  assert_missing "$HOME_DIR/Downloads/disk-cleanup-selection (1).json"
  assert_exists "$HOME_DIR/Downloads/disk-cleanup-selection-7.json"
  assert_exists "$HOME_DIR/Downloads/unrelated-fresh.txt"
  write_selection "$TOKEN" "$ARCHIVE_ID"
  apply_review
  assert_error TOKEN_INVALID
  assert_exists "$ARCHIVE"
}

@test "no saved selection reports SELECTION_NOT_FOUND and keeps the token" {
  apply_review
  assert_error SELECTION_NOT_FOUND
  assert_exists "$MANIFEST"
  write_selection "$TOKEN" "$VIDEO_ID"
  apply_review
  [ "$(count trashed_count)" = "1" ]
}

@test "selection files elsewhere, symlinked or oddly named do not count" {
  mkdir -p "$HOME_DIR/Downloads/sub" "$HOME_DIR/Documents"
  printf '{"token":"%s","secret":"%s","ids":[%s]}' "$TOKEN" "$SECRET" "$VIDEO_ID" > "$HOME_DIR/Downloads/sub/$SELECTION_NAME"
  printf '{"token":"%s","secret":"%s","ids":[%s]}' "$TOKEN" "$SECRET" "$VIDEO_ID" > "$HOME_DIR/Documents/$SELECTION_NAME"
  printf '{"token":"%s","secret":"%s","ids":[%s]}' "$TOKEN" "$SECRET" "$VIDEO_ID" > "$OUTSIDE/real-selection"
  ln -s "$OUTSIDE/real-selection" "$HOME_DIR/Downloads/$SELECTION_NAME"
  write_selection "$TOKEN" "$VIDEO_ID" "disk-cleanup-selection-final.json"
  write_selection "$TOKEN" "$VIDEO_ID" "my-disk-cleanup-selection.json"
  write_selection "$TOKEN" "$VIDEO_ID" "disk-cleanup-selection.json.txt"
  mkdir -p "$HOME_DIR/Downloads/disk-cleanup-selection (2).json"
  apply_review
  assert_error SELECTION_NOT_FOUND
  assert_exists "$VIDEO"
  assert_exists "$OUTSIDE/real-selection"
}

@test "a selection for another token is rejected and nothing moves" {
  write_selection "0badc0de" "$VIDEO_ID"
  apply_review
  assert_error SELECTION_INVALID
  assert_exists "$VIDEO"
  assert_exists "$MANIFEST"
  assert_exists "$HOME_DIR/Downloads/$SELECTION_NAME"
}

@test "malformed selections are rejected" {
  local body bodies=(
    "{\"token\":\"$TOKEN\",\"secret\":\"$SECRET\",\"ids\":[1,2],\"extra\":true}"
    "{\"token\":\"$TOKEN\",\"secret\":\"$SECRET\",\"ids\":[1,2]} trailing"
    "{\"token\":\"$TOKEN\",\"secret\":\"$SECRET\",\"ids\":[1,,2]}"
    "{\"token\":\"$TOKEN\",\"secret\":\"$SECRET\",\"ids\":[1,2,]}"
    "{\"token\":\"$TOKEN\",\"secret\":\"$SECRET\",\"ids\":[-1]}"
    "{\"token\":\"$TOKEN\",\"secret\":\"$SECRET\",\"ids\":[\"1\"]}"
    "{\"token\":\"$TOKEN\",\"secret\":\"$SECRET\",\"ids\":[1.5]}"
    "{\"token\":\"$TOKEN\",\"secret\":\"$SECRET\",\"ids\":[1 2]}"
    "{\"ids\":[1],\"secret\":\"$SECRET\",\"token\":\"$TOKEN\"}"
    "{\"secret\":\"$SECRET\",\"token\":\"$TOKEN\",\"ids\":[1]}"
    "{\"token\":\"${TOKEN}0\",\"secret\":\"$SECRET\",\"ids\":[1]}"
    "{\"token\":\"$TOKEN\",\"secret\":\"${SECRET}0\",\"ids\":[1]}"
    "{\"token\":\"$TOKEN\",\"secret\":\"${SECRET%?}\",\"ids\":[1]}"
    "{\"token\":\"$TOKEN\",\"secret\":\"\",\"ids\":[1]}"
    "{\"token\":\"$TOKEN\",\"secret\":\"$SECRET\",\"secret\":\"$SECRET\",\"ids\":[1]}"
    "{'token':'$TOKEN','secret':'$SECRET','ids':[1]}"
    "{\"token\":\"$TOKEN\",\"secret\":\"$SECRET\",\"ids\":[\$(touch $HOME_DIR/pwned)]}"
    "token=$TOKEN; touch $HOME_DIR/pwned"
    ""
  )
  for body in "${bodies[@]}"; do
    printf '%s' "$body" > "$HOME_DIR/Downloads/$SELECTION_NAME"
    apply_review
    assert_error SELECTION_INVALID
  done
  assert_missing "$HOME_DIR/pwned"
  assert_exists "$VIDEO"
  assert_exists "$MANIFEST"
}

@test "an upper-case token in the selection is rejected" {
  local upper
  upper=$(printf '%s' "$TOKEN" | /usr/bin/tr 'a-f' 'A-F')
  printf '{"token":"%s","secret":"%s","ids":[%s]}' "${upper}" "$SECRET" "$VIDEO_ID" > "$HOME_DIR/Downloads/$SELECTION_NAME"
  [ "$upper" != "$TOKEN" ] || skip "token has no letters"
  apply_review
  assert_error SELECTION_INVALID
}

@test "an oversized selection is rejected without being parsed" {
  {
    printf '{"token":"%s","secret":"%s","ids":[%s' "$TOKEN" "$SECRET" "$VIDEO_ID"
    head -c 1100000 /dev/zero | /usr/bin/tr '\0' ' '
    printf ']}'
  } > "$HOME_DIR/Downloads/$SELECTION_NAME"
  apply_review
  assert_error SELECTION_INVALID
  assert_exists "$VIDEO"
}

@test "whitespace in the selection is tolerated" {
  printf ' {\n  "token" : "%s" ,\r\n "secret"\t: "%s" ,\n\t"ids" : [ %s ,\n %s ]\n}\n' "$TOKEN" "$SECRET" "$VIDEO_ID" "$FORM_ID" \
    > "$HOME_DIR/Downloads/$SELECTION_NAME"
  apply_review
  [ "$status" -eq 0 ]
  [ "$(count trashed_count)" = "2" ]
}

@test "browser duplicate names are accepted and the newest matching file wins" {
  write_selection "$TOKEN" "$ARCHIVE_ID" "disk-cleanup-selection.json"
  age_path "$HOME_DIR/Downloads/disk-cleanup-selection.json" 1
  write_selection "0badc0de" "$IMAGE_ID" "disk-cleanup-selection-2.json"
  write_selection "$TOKEN" "$VIDEO_ID" "disk-cleanup-selection (3).json"
  apply_review
  [ "$status" -eq 0 ]
  [ "$(count selected_count)" = "1" ]
  trash_holds "walrus-video.mov"
  assert_exists "$ARCHIVE"
  assert_exists "$IMAGE"
}

@test "a folder that cannot be modified counts as no permission and keeps the file" {
  chmod 555 "$HOME_DIR/Movies/trip"
  write_selection "$TOKEN" "$VIDEO_ID,$ARCHIVE_ID"
  apply_review
  assert_json_schema review-apply
  [ "$(count skipped_no_permission_count)" = "1" ]
  [ "$(count trashed_count)" = "1" ]
  assert_exists "$VIDEO"
}

@test "a Trash that cannot be written keeps every file in place" {
  mkdir -p "$TRASH"
  chmod 500 "$TRASH"
  write_selection "$TOKEN" "$VIDEO_ID"
  apply_review
  [ "$(count skipped_no_permission_count)" = "1" ]
  [ "$(count trashed_count)" = "0" ]
  assert_exists "$VIDEO"
}

@test "a Trash that is a symlink is never used" {
  mkdir -p "$OUTSIDE/fake-trash"
  ln -s "$OUTSIDE/fake-trash" "$TRASH"
  write_selection "$TOKEN" "$VIDEO_ID"
  apply_review
  [ "$(count trashed_count)" = "0" ]
  assert_exists "$VIDEO"
  [ -z "$(/bin/ls -A "$OUTSIDE/fake-trash")" ]
}

@test "nothing is ever destroyed: every ticked file still exists somewhere" {
  local before after
  before=$(/usr/bin/find "$HOME_DIR" -type f -size +10M | /usr/bin/wc -l)
  write_selection "$TOKEN" "$VIDEO_ID,$ARCHIVE_ID,$IMAGE_ID,$FORM_ID"
  apply_review
  [ "$(count trashed_count)" = "4" ]
  after=$(/usr/bin/find "$HOME_DIR" -type f -size +10M | /usr/bin/wc -l)
  [ "$before" = "$after" ]
  trash_holds "ibis-form.pdf"
}

@test "review-apply writes nothing to stderr and leaves the scan token alone" {
  make_chrome_profile
  run_cleanup scan
  local scan_token
  scan_token=$(json get token)
  write_selection "$TOKEN" "$VIDEO_ID"
  run --separate-stderr sandbox_env /bin/bash "$CLEANUP" review-apply --token "$TOKEN"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  run_cleanup clean --token "$scan_token" --categories browser-chrome
  [ "$status" -eq 0 ]
}

# --- the selection secret: a selection made from the token alone is refused ---

@test "a forged selection without the secret is rejected and left alone" {
  write_forged_selection "$TOKEN" "$VIDEO_ID,$ARCHIVE_ID"
  apply_review
  assert_error SELECTION_INVALID
  assert_exists "$VIDEO"
  assert_exists "$ARCHIVE"
  assert_missing "$TRASH/walrus-video.mov"
  assert_exists "$MANIFEST"
  assert_exists "$HOME_DIR/Downloads/$SELECTION_NAME"
  [[ "$output" != *"$SECRET"* ]]
}

@test "a selection with a wrong secret is rejected and left alone" {
  local wrong
  for wrong in "00000000000000000000000000000000" "$TOKEN$TOKEN$TOKEN$TOKEN" \
    "$(printf '%s' "$SECRET" | /usr/bin/tr 'a-f' 'A-F')X" "${SECRET%?}"; do
    write_selection "$TOKEN" "$VIDEO_ID" "$SELECTION_NAME" "$wrong"
    apply_review
    assert_error SELECTION_INVALID
    assert_exists "$HOME_DIR/Downloads/$SELECTION_NAME"
  done
  assert_exists "$VIDEO"
  assert_exists "$MANIFEST"
}

@test "the user's own selection still works after a forged one was refused" {
  write_forged_selection "$TOKEN" "$ARCHIVE_ID"
  apply_review
  assert_error SELECTION_INVALID
  write_selection "$TOKEN" "$VIDEO_ID" "disk-cleanup-selection (1).json"
  apply_review
  [ "$status" -eq 0 ]
  [ "$(count trashed_count)" = "1" ]
  trash_holds "walrus-video.mov"
  assert_exists "$ARCHIVE"
  assert_exists "$HOME_DIR/Downloads/$SELECTION_NAME"
  assert_missing "$HOME_DIR/Downloads/disk-cleanup-selection (1).json"
}

@test "review-apply output never contains the secret" {
  write_selection "$TOKEN" "$VIDEO_ID"
  run --separate-stderr sandbox_env /bin/bash "$CLEANUP" review-apply --token "$TOKEN"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" != *"$SECRET"* ]]
}

# --- the manifest is not trusted: integrity line plus a re-check of each rule ---

small_file_line() {
  local id=$1 group=$2 path=$3 blocks
  blocks=$(/usr/bin/stat -f '%b' "$path")
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$((blocks * 512))" "$(/usr/bin/stat -f '%z' "$path")" \
    "$(/usr/bin/stat -f '%m' "$path")" "$group" "$path"
}

@test "a line appended to the manifest breaks the integrity check and nothing moves" {
  make_file "$HOME_DIR/Documents/tax-letter.txt" 16
  small_file_line 77 large-files "$HOME_DIR/Documents/tax-letter.txt" >> "$MANIFEST"
  write_selection "$TOKEN" "77,$VIDEO_ID"
  apply_review
  assert_error SELECTION_INVALID
  assert_exists "$HOME_DIR/Documents/tax-letter.txt"
  assert_exists "$VIDEO"
  assert_missing "$TRASH"
  assert_private tax-letter walrus-video
}

@test "an edited or removed manifest line breaks the integrity check" {
  /usr/bin/sed -i '' "s|$ARCHIVE\$|$IMAGE|" "$MANIFEST"
  write_selection "$TOKEN" "$ARCHIVE_ID"
  apply_review
  assert_error SELECTION_INVALID
  assert_exists "$IMAGE"
  review_for_token
  /usr/bin/sed -i '' '$d' "$MANIFEST"
  write_selection "$TOKEN" "$VIDEO_ID"
  apply_review
  assert_error SELECTION_INVALID
  assert_exists "$VIDEO"
}

@test "a tampered integrity line or secret is rejected" {
  /usr/bin/sed -i '' 's/^integrity=.*/integrity=0000000000000000000000000000000000000000000000000000000000000000/' "$MANIFEST"
  write_selection "$TOKEN" "$VIDEO_ID"
  apply_review
  assert_error SELECTION_INVALID
  assert_exists "$VIDEO"
  review_for_token
  /usr/bin/sed -i '' 's/^secret=.*/secret=00000000000000000000000000000000/' "$MANIFEST"
  write_selection "$TOKEN" "$VIDEO_ID" "$SELECTION_NAME" "00000000000000000000000000000000"
  apply_review
  assert_error SELECTION_INVALID
  assert_exists "$VIDEO"
}

@test "even a re-sealed manifest cannot add a small file: the large-files rule is checked again" {
  make_file "$HOME_DIR/Documents/tax-letter.txt" 16
  small_file_line 77 large-files "$HOME_DIR/Documents/tax-letter.txt" >> "$MANIFEST"
  reseal_manifest
  write_selection "$TOKEN" "77,$VIDEO_ID"
  apply_review
  [ "$status" -eq 0 ]
  [ "$(count skipped_changed_count)" = "1" ]
  [ "$(count trashed_count)" = "1" ]
  assert_exists "$HOME_DIR/Documents/tax-letter.txt"
  trash_holds "walrus-video.mov"
}

@test "even a re-sealed manifest cannot add old-downloads items outside Downloads or newer than the threshold" {
  make_file "$HOME_DIR/Documents/old-letter.txt" 16
  age_path "$HOME_DIR/Documents/old-letter.txt" 400
  make_file "$HOME_DIR/Downloads/sub/old-nested.txt" 16
  age_path "$HOME_DIR/Downloads/sub/old-nested.txt" 400
  age_path "$HOME_DIR/Downloads/unrelated-fresh.txt" 30
  {
    small_file_line 81 old-downloads "$HOME_DIR/Documents/old-letter.txt"
    small_file_line 82 old-downloads "$HOME_DIR/Downloads/sub/old-nested.txt"
    small_file_line 83 old-downloads "$HOME_DIR/Downloads/unrelated-fresh.txt"
    small_file_line 84 other-group "$HOME_DIR/Downloads/ibis-form.pdf"
  } >> "$MANIFEST"
  reseal_manifest
  write_selection "$TOKEN" "81,82,83,84,$FORM_ID"
  apply_review
  [ "$status" -eq 0 ]
  [ "$(count selected_count)" = "5" ]
  [ "$(count skipped_changed_count)" = "3" ]
  [ "$(count ignored_count)" = "1" ]
  [ "$(count trashed_count)" = "1" ]
  assert_exists "$HOME_DIR/Documents/old-letter.txt"
  assert_exists "$HOME_DIR/Downloads/sub/old-nested.txt"
  assert_exists "$HOME_DIR/Downloads/unrelated-fresh.txt"
  trash_holds "ibis-form.pdf"
}

@test "review options in the header are validated and cannot be loosened below the floors" {
  /usr/bin/sed -i '' 's/^min_size_mb=.*/min_size_mb=1/' "$MANIFEST"
  write_selection "$TOKEN" "$VIDEO_ID"
  apply_review
  assert_error TOKEN_INVALID
  assert_exists "$VIDEO"
  review_for_token
  /usr/bin/sed -i '' 's/^downloads_age_days=.*/downloads_age_days=0/' "$MANIFEST"
  write_selection "$TOKEN" "$VIDEO_ID"
  apply_review
  assert_error TOKEN_INVALID
  assert_exists "$VIDEO"
}

@test "a re-sealed manifest pointing at a name with bidirectional controls is refused" {
  local spoof="$HOME_DIR/Documents/invoice-"$'\xe2\x80\xae'"fdp.exe"
  make_big_file "$spoof" 11
  repoint_manifest "$ARCHIVE_ID" "$spoof"
  write_selection "$TOKEN" "$ARCHIVE_ID"
  apply_review
  [ "$(count skipped_changed_count)" = "1" ]
  [ "$(count trashed_count)" = "0" ]
  assert_exists "$spoof"
}
