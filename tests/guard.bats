#!/usr/bin/env bats

load helpers/common

setup() {
  setup_sandbox
  CACHE="$SANDBOX_HOME/Library/Caches/com.example.editor"
  make_file "$CACHE/inner/data.bin" 4
  make_file "$OUTSIDE/precious/keep.txt" 4
}
teardown() { teardown_sandbox; }

guard() { run_function guarded_delete "$@"; }

@test "guard: deletes the contents of an allowed directory and keeps the directory" {
  guard contents "$CACHE"
  [ "$status" -eq 0 ]
  [ -d "$CACHE" ]
  assert_missing "$CACHE/inner"
}

@test "guard: refuses an empty target" {
  guard contents ""
  [ "$status" -ne 0 ]
  guard tree
  [ "$status" -ne 0 ]
  assert_exists "$CACHE/inner/data.bin"
}

@test "guard: refuses a relative target" {
  cd "$SANDBOX_HOME/Library"
  guard contents "Caches/com.example.editor"
  [ "$status" -ne 0 ]
  guard contents "./Caches/com.example.editor"
  [ "$status" -ne 0 ]
  assert_exists "$CACHE/inner/data.bin"
}

@test "guard: refuses the home directory itself" {
  guard contents "$SANDBOX_HOME"
  [ "$status" -ne 0 ]
  guard tree "$SANDBOX_HOME/"
  [ "$status" -ne 0 ]
  assert_exists "$CACHE/inner/data.bin"
}

@test "guard: refuses the filesystem root" {
  guard contents "/"
  [ "$status" -ne 0 ]
  assert_exists "$CACHE/inner/data.bin"
}

@test "guard: refuses targets less than two levels below home" {
  make_file "$SANDBOX_HOME/projects/app.txt" 4
  guard contents "$SANDBOX_HOME/Library"
  [ "$status" -ne 0 ]
  guard tree "$SANDBOX_HOME/projects"
  [ "$status" -ne 0 ]
  assert_exists "$CACHE/inner/data.bin"
  assert_exists "$SANDBOX_HOME/projects/app.txt"
}

@test "guard: refuses a target outside the home directory" {
  guard contents "$OUTSIDE/precious"
  [ "$status" -ne 0 ]
  guard file "$OUTSIDE/precious/keep.txt"
  [ "$status" -ne 0 ]
  assert_exists "$OUTSIDE/precious/keep.txt"
}

@test "guard: refuses a target that is a symlink" {
  ln -s "$OUTSIDE/precious" "$SANDBOX_HOME/Library/Caches/link-out"
  ln -s "$CACHE" "$SANDBOX_HOME/Library/Caches/link-in"
  guard contents "$SANDBOX_HOME/Library/Caches/link-out"
  [ "$status" -ne 0 ]
  guard contents "$SANDBOX_HOME/Library/Caches/link-out/"
  [ "$status" -ne 0 ]
  guard tree "$SANDBOX_HOME/Library/Caches/link-in"
  [ "$status" -ne 0 ]
  assert_exists "$OUTSIDE/precious/keep.txt"
  assert_exists "$CACHE/inner/data.bin"
  assert_exists "$SANDBOX_HOME/Library/Caches/link-in"
}

@test "guard: refuses a path that leaves home through a symlinked parent" {
  mkdir -p "$OUTSIDE/precious/sub"
  make_file "$OUTSIDE/precious/sub/keep.txt" 4
  ln -s "$OUTSIDE/precious" "$SANDBOX_HOME/Library/Caches/link-out"
  guard contents "$SANDBOX_HOME/Library/Caches/link-out/sub"
  [ "$status" -ne 0 ]
  assert_exists "$OUTSIDE/precious/sub/keep.txt"
}

@test "guard: a symlink inside the tree is removed without following it" {
  ln -s "$OUTSIDE/precious" "$CACHE/inner/escape"
  ln -s "$OUTSIDE/precious/keep.txt" "$CACHE/file-link"
  guard contents "$CACHE"
  [ "$status" -eq 0 ]
  assert_missing "$CACHE/inner"
  assert_missing "$CACHE/file-link"
  assert_exists "$OUTSIDE/precious/keep.txt"
}

@test "guard: refuses dot-dot traversal into protected folders" {
  make_file "$SANDBOX_HOME/Documents/thesis/chapter.txt" 4
  guard contents "$SANDBOX_HOME/Library/Caches/../../Documents/thesis"
  [ "$status" -ne 0 ]
  guard tree "$CACHE/inner/.."
  [ "$status" -ne 0 ]
  assert_exists "$SANDBOX_HOME/Documents/thesis/chapter.txt"
  assert_exists "$CACHE/inner/data.bin"
}

@test "guard: refuses personal folders" {
  local folder
  for folder in Documents Desktop Downloads Pictures Movies Music; do
    make_file "$SANDBOX_HOME/$folder/album/item.bin" 4
    guard contents "$SANDBOX_HOME/$folder/album"
    [ "$status" -ne 0 ]
    guard file "$SANDBOX_HOME/$folder/album/item.bin"
    [ "$status" -ne 0 ]
    assert_exists "$SANDBOX_HOME/$folder/album/item.bin"
  done
}

@test "guard: refuses cloud-drive folders" {
  make_file "$SANDBOX_HOME/Library/Mobile Documents/com~apple~CloudDocs/note.txt" 4
  make_file "$SANDBOX_HOME/Library/CloudStorage/Drive/sheet.bin" 4
  make_file "$SANDBOX_HOME/Dropbox/shared/file.bin" 4
  guard contents "$SANDBOX_HOME/Library/Mobile Documents/com~apple~CloudDocs"
  [ "$status" -ne 0 ]
  guard contents "$SANDBOX_HOME/Library/CloudStorage/Drive"
  [ "$status" -ne 0 ]
  guard contents "$SANDBOX_HOME/Dropbox/shared"
  [ "$status" -ne 0 ]
  assert_exists "$SANDBOX_HOME/Dropbox/shared/file.bin"
}

@test "guard: refuses personal folders regardless of letter case" {
  make_file "$SANDBOX_HOME/Documents/thesis/chapter.txt" 4
  guard contents "$SANDBOX_HOME/documents/thesis"
  [ "$status" -ne 0 ]
  assert_exists "$SANDBOX_HOME/Documents/thesis/chapter.txt"
}

@test "guard: only a node_modules directory may be removed below a personal folder" {
  make_file "$SANDBOX_HOME/Documents/app/node_modules/pkg/index.js" 4
  make_file "$SANDBOX_HOME/Documents/app/src/index.js" 4
  guard contents "$SANDBOX_HOME/Documents/app/node_modules"
  [ "$status" -ne 0 ]
  guard tree "$SANDBOX_HOME/Documents/app/src"
  [ "$status" -ne 0 ]
  guard tree "$SANDBOX_HOME/Documents/app/node_modules"
  [ "$status" -eq 0 ]
  assert_missing "$SANDBOX_HOME/Documents/app/node_modules"
  assert_exists "$SANDBOX_HOME/Documents/app/src/index.js"
}

@test "guard: never touches Xcode archives or keychains" {
  make_file "$SANDBOX_HOME/Library/Developer/Xcode/Archives/2026/App.xcarchive/Info.plist" 4
  make_file "$SANDBOX_HOME/Library/Keychains/login.keychain-db" 4
  guard contents "$SANDBOX_HOME/Library/Developer/Xcode/Archives"
  [ "$status" -ne 0 ]
  guard tree "$SANDBOX_HOME/Library/Developer/Xcode/Archives/2026"
  [ "$status" -ne 0 ]
  guard file "$SANDBOX_HOME/Library/Keychains/login.keychain-db"
  [ "$status" -ne 0 ]
  assert_exists "$SANDBOX_HOME/Library/Developer/Xcode/Archives/2026/App.xcarchive/Info.plist"
  assert_exists "$SANDBOX_HOME/Library/Keychains/login.keychain-db"
}

@test "guard: refuses an ancestor of a never-touch folder" {
  make_file "$SANDBOX_HOME/Library/Developer/Xcode/Archives/2026/App.xcarchive/Info.plist" 4
  make_file "$SANDBOX_HOME/Library/Developer/Xcode/DerivedData/App/object.o" 4
  local mode
  for mode in contents tree old-files; do
    guard "$mode" "$SANDBOX_HOME/Library/Developer" 1
    [ "$status" -ne 0 ]
    guard "$mode" "$SANDBOX_HOME/Library/Developer/Xcode" 1
    [ "$status" -ne 0 ]
    guard "$mode" "$SANDBOX_HOME/library/developer/xcode" 1
    [ "$status" -ne 0 ]
  done
  assert_exists "$SANDBOX_HOME/Library/Developer/Xcode/Archives/2026/App.xcarchive/Info.plist"
  assert_exists "$SANDBOX_HOME/Library/Developer/Xcode/DerivedData/App/object.o"
  guard contents "$SANDBOX_HOME/Library/Developer/Xcode/DerivedData"
  [ "$status" -eq 0 ]
  assert_missing "$SANDBOX_HOME/Library/Developer/Xcode/DerivedData/App"
}

@test "guard: tree mode accepts only a directory named exactly node_modules" {
  make_file "$SANDBOX_HOME/code/app/node_modules/pkg/index.js" 4
  make_file "$SANDBOX_HOME/code/app/node_modules_backup/pkg/index.js" 4
  make_file "$SANDBOX_HOME/code/app/src/index.js" 4
  guard tree "$CACHE"
  [ "$status" -ne 0 ]
  guard tree "$CACHE/inner"
  [ "$status" -ne 0 ]
  guard tree "$SANDBOX_HOME/code/app/src"
  [ "$status" -ne 0 ]
  guard tree "$SANDBOX_HOME/code/app/node_modules_backup"
  [ "$status" -ne 0 ]
  guard tree "$SANDBOX_HOME/code/app/node_modules/pkg"
  [ "$status" -ne 0 ]
  assert_exists "$CACHE/inner/data.bin"
  assert_exists "$SANDBOX_HOME/code/app/node_modules_backup/pkg/index.js"
  assert_exists "$SANDBOX_HOME/code/app/node_modules/pkg/index.js"
  guard tree "$SANDBOX_HOME/code/app/node_modules"
  [ "$status" -eq 0 ]
  assert_missing "$SANDBOX_HOME/code/app/node_modules"
  assert_exists "$SANDBOX_HOME/code/app/src/index.js"
}

@test "guard: empty-dir mode removes a directory only when it is empty" {
  mkdir -p "$CACHE/hollow"
  guard empty-dir "$CACHE/inner"
  [ "$status" -ne 0 ]
  assert_exists "$CACHE/inner/data.bin"
  guard empty-dir "$CACHE/hollow"
  [ "$status" -eq 0 ]
  assert_missing "$CACHE/hollow"
  mkdir -p "$SANDBOX_HOME/Documents/hollow"
  guard empty-dir "$SANDBOX_HOME/Documents/hollow"
  [ "$status" -ne 0 ]
  [ -d "$SANDBOX_HOME/Documents/hollow" ]
}

@test "guard: refuses the temp root itself but accepts entries inside it" {
  make_file "$SANDBOX_TMP/session/scratch.bin" 4
  guard contents "$SANDBOX_TMP"
  [ "$status" -ne 0 ]
  assert_exists "$SANDBOX_TMP/session/scratch.bin"
  guard file "$SANDBOX_TMP/session/scratch.bin"
  [ "$status" -eq 0 ]
  assert_missing "$SANDBOX_TMP/session/scratch.bin"
}

@test "guard: file mode refuses directories and tree mode refuses files" {
  guard file "$CACHE/inner"
  [ "$status" -ne 0 ]
  guard tree "$CACHE/inner/data.bin"
  [ "$status" -ne 0 ]
  assert_exists "$CACHE/inner/data.bin"
}

@test "guard: refuses an unknown mode" {
  guard everything "$CACHE"
  [ "$status" -ne 0 ]
  assert_exists "$CACHE/inner/data.bin"
}

@test "guard: old-files mode removes only regular files past the age" {
  make_file "$CACHE/stale.bin" 4
  age_path "$CACHE/stale.bin" 20
  ln -s "$OUTSIDE/precious/keep.txt" "$CACHE/old-link"
  age_path "$CACHE/old-link" 20
  guard old-files "$CACHE" 7
  [ "$status" -eq 0 ]
  assert_missing "$CACHE/stale.bin"
  assert_exists "$CACHE/inner/data.bin"
  assert_exists "$CACHE/old-link"
  guard old-files "$CACHE" 0
  [ "$status" -ne 0 ]
  guard old-files "$CACHE"
  [ "$status" -ne 0 ]
  assert_exists "$CACHE/inner/data.bin"
}

@test "guard: the trash is the only first-level folder whose contents may go" {
  make_file "$SANDBOX_HOME/.Trash/discarded.bin" 4
  guard tree "$SANDBOX_HOME/.Trash"
  [ "$status" -ne 0 ]
  guard contents "$SANDBOX_HOME/.Trash"
  [ "$status" -eq 0 ]
  [ -d "$SANDBOX_HOME/.Trash" ]
  assert_missing "$SANDBOX_HOME/.Trash/discarded.bin"
}

@test "guard: an undeletable entry is reported, not fatal" {
  make_file "$CACHE/locked/data.bin" 4
  chmod 500 "$CACHE/locked"
  guard contents "$CACHE"
  [ "$status" -ne 0 ]
  assert_exists "$CACHE/locked/data.bin"
  assert_missing "$CACHE/inner"
}

@test "only the guard routine contains a deleting command" {
  local offenders
  offenders=$(grep -nE '(^|[^[:alnum:]_-])(rm|rmdir|unlink)[[:space:]]|-delete|-exec[[:space:]]+rm' \
    "$PROJECT_ROOT"/scripts/cleanup.sh "$PROJECT_ROOT"/scripts/lib/*.sh | grep -v '^[^:]*guard\.sh:' || true)
  [ -z "$offenders" ] || { echo "$offenders"; return 1; }
  [ "$(grep -c -- '-delete' "$PROJECT_ROOT/scripts/lib/guard.sh")" -eq 1 ]
}
