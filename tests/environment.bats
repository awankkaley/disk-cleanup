#!/usr/bin/env bats

load helpers/common

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

@test "a HOME strictly inside the account's real home is refused" {
  make_file "$SANDBOX_HOME/Library/Caches/com.example.editor/data.bin" 8
  stub_account_home "$SANDBOX"
  run_cleanup scan
  assert_error INTERNAL
  [ ! -e "$STATE_DIR" ]
}

@test "a HOME equal to the account's real home is accepted" {
  stub_account_home "$SANDBOX_HOME"
  run_cleanup scan
  [ "$status" -eq 0 ]
  assert_json_schema scan
}

@test "a sandbox HOME outside the account's real home is accepted" {
  mkdir -p "$SANDBOX/account"
  stub_account_home "$SANDBOX/account"
  run_cleanup scan
  [ "$status" -eq 0 ]
}

@test "the real home is compared after physical resolution" {
  ln -s "$SANDBOX" "$SANDBOX/alias"
  stub_account_home "$SANDBOX/alias"
  run_cleanup scan
  assert_error INTERNAL
}

@test "a multi-line directory service answer is understood" {
  stub_tool dscl "echo 'NFSHomeDirectory:'; echo ' $SANDBOX'"
  run_cleanup scan
  assert_error INTERNAL
}

@test "the passwd entry is used when the directory service has no answer" {
  stub_tool dscl "exit 1"
  stub_tool id "case \"\$1\" in
    -un) echo tester ;;
    -P) echo 'tester:*:501:20::0:0:Test User:$SANDBOX:/bin/zsh' ;;
  esac"
  run_cleanup scan
  assert_error INTERNAL
  stub_tool id "case \"\$1\" in
    -un) echo tester ;;
    -P) echo 'tester:*:501:20::0:0:Test User:$SANDBOX_HOME:/bin/zsh' ;;
  esac"
  run_cleanup scan
  [ "$status" -eq 0 ]
}

@test "an account home that cannot be determined is refused" {
  stub_tool dscl "exit 1"
  stub_tool id "exit 1"
  run_cleanup scan
  assert_error INTERNAL
}

@test "clean is refused as well when HOME is redirected into the real home" {
  make_chrome_profile
  scan_for_token
  stub_account_home "$SANDBOX"
  clean_categories browser-chrome
  assert_error INTERNAL
  assert_exists "$CHROME_CACHE/Cache/Cache_Data/blob-one"
}

@test "temp root shape: exactly two single segments before T" {
  run_function temp_root_has_shape /private/var/folders/zz/abc123/T
  [ "$status" -eq 0 ]
  run_function temp_root_has_shape /private/var/folders/zz/abc123/T/sub/dir
  [ "$status" -eq 0 ]
  run_function temp_root_has_shape /private/var/folders/zz/abc123/extra/T
  [ "$status" -ne 0 ]
  run_function temp_root_has_shape /private/var/folders/zz/abc123/extra/more/T/sub
  [ "$status" -ne 0 ]
  run_function temp_root_has_shape /private/var/folders/zz/T
  [ "$status" -ne 0 ]
  run_function temp_root_has_shape /private/var/folders/zz/abc123/Tx
  [ "$status" -ne 0 ]
  run_function temp_root_has_shape /private/var/folders/zz//T
  [ "$status" -ne 0 ]
}

@test "a TMPDIR nested deeper than the per-user temp dir pattern is not a temp root" {
  local base deep
  base=$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)
  base=$(cd -P "$base/.." && pwd -P)
  deep="$SANDBOX/x/T"
  mkdir -p "$deep"
  run_function temp_root_is_sane "$deep"
  [ "$status" -eq 0 ]
  run_function temp_root_has_shape "$base/C/nested/T"
  [ "$status" -ne 0 ]
}
