#!/bin/bash
# Shared bats helpers. Every cleanup.sh invocation gets a throwaway HOME and
# TMPDIR plus a PATH made only of stubs, a curated toolbin and /bin, so no real
# developer tool, process list or user file can ever be reached.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLEANUP="$PROJECT_ROOT/scripts/cleanup.sh"
JSON_TOOL="$PROJECT_ROOT/tests/helpers/json.pl"
SYSTEM_TOOLS="find du stat awk od tr uname readlink id dscl"
SANDBOX_MARKER="disk-cleanup-test"

setup_sandbox() {
  local base tool
  base=$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)
  SANDBOX=$(/usr/bin/mktemp -d "${base%/}/$SANDBOX_MARKER.XXXXXXXX")
  SANDBOX=$(cd -P "$SANDBOX" && pwd -P)
  SANDBOX_HOME="$SANDBOX/home"
  SANDBOX_TMP="$SANDBOX/tmp"
  STUB_BIN="$SANDBOX/stubs"
  TOOL_BIN="$SANDBOX/toolbin"
  OUTSIDE="$SANDBOX/outside"
  STUB_LOG="$SANDBOX/stub.log"
  RUNNING_FILE="$SANDBOX/running-processes"
  RUNNING_APPS_FILE="$SANDBOX/running-apps"
  STATE_DIR="$SANDBOX_HOME/Library/Application Support/disk-cleanup"
  mkdir -p "$SANDBOX_HOME/Library" "$SANDBOX_TMP" "$STUB_BIN" "$TOOL_BIN" "$OUTSIDE"
  : > "$STUB_LOG"
  : > "$RUNNING_FILE"
  : > "$RUNNING_APPS_FILE"
  for tool in $SYSTEM_TOOLS; do
    ln -s "/usr/bin/$tool" "$TOOL_BIN/$tool"
  done
}

teardown_sandbox() {
  case "${SANDBOX:-}" in
    */"$SANDBOX_MARKER".*)
      chmod -R u+rwX "$SANDBOX" 2>/dev/null
      rm -rf "$SANDBOX"
      ;;
  esac
}

sandbox_env() {
  [ -n "${SANDBOX_HOME:-}" ] || return 99
  env -i HOME="$SANDBOX_HOME" TMPDIR="$SANDBOX_TMP" \
    PATH="$STUB_BIN:$TOOL_BIN:/bin" "$@"
}

run_cleanup() {
  run sandbox_env /bin/bash "$CLEANUP" "$@"
}

# Calls a function of the script directly (after environment initialisation).
run_function() {
  run sandbox_env /bin/bash -c \
    'source "$1"; shift; init_environment; LOG_FILE=""; "$@"' _ "$CLEANUP" "$@"
}

make_file() {
  local path=$1 kilobytes=${2:-4}
  mkdir -p "$(dirname "$path")"
  head -c "$((kilobytes * 1024))" /dev/zero > "$path"
}

age_path() {
  touch -h -t "$(date -v-"$2"d +%Y%m%d%H%M.%S)" "$1"
}

age_tree() {
  find "$1" -exec touch -h -t "$(date -v-"$2"d +%Y%m%d%H%M.%S)" {} +
}

# stub_tool NAME BODY: fake executable that records its arguments.
stub_tool() {
  local name=$1 body=${2:-exit 0}
  {
    printf '#!/bin/bash\n'
    printf 'echo "%s $*" >> "%s"\n' "$name" "$STUB_LOG"
    printf '%s\n' "$body"
  } > "$STUB_BIN/$name"
  chmod +x "$STUB_BIN/$name"
}

# stub_cache_tool NAME REPORT_ARGS DIR [BODY]: fake tool that prints DIR when
# asked where its cache is and otherwise runs BODY.
stub_cache_tool() {
  local name=$1 report=$2 dir=$3 body=${4:-exit 0}
  stub_tool "$name" "if [ \"\$*\" = \"$report\" ]; then echo \"$dir\"; exit 0; fi
$body"
}

# stub_account_home DIR: the directory service reports DIR as the real home.
stub_account_home() {
  stub_tool dscl "echo \"NFSHomeDirectory: $1\""
}

# Fake pgrep: a process "runs" when its pattern is a line of RUNNING_FILE;
# list mode prints RUNNING_APPS_FILE.
install_pgrep_stub() {
  cat > "$STUB_BIN/pgrep" <<EOF
#!/bin/bash
pattern=""
for argument in "\$@"; do pattern=\$argument; done
if [ "\$1" = "-lf" ]; then
  /bin/cat "$RUNNING_APPS_FILE"
  exit 0
fi
while IFS= read -r line; do
  if [ "\$line" = "\$pattern" ]; then echo 4242; exit 0; fi
done < "$RUNNING_FILE"
exit 1
EOF
  chmod +x "$STUB_BIN/pgrep"
}

mark_running() {
  install_pgrep_stub
  printf '%s\n' "$1" >> "$RUNNING_FILE"
}

# mark_app_running NAME BUNDLE_ID: fake running .app bundle with an Info.plist.
mark_app_running() {
  local name=$1 bundle_id=$2 app="$SANDBOX/Applications/$1.app"
  install_pgrep_stub
  mkdir -p "$app/Contents/MacOS"
  cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>$bundle_id</string></dict></plist>
EOF
  printf '777 %s/Contents/MacOS/%s --flag\n' "$app" "$name" >> "$RUNNING_APPS_FILE"
}

json() {
  printf '%s' "$output" | /usr/bin/perl "$JSON_TOOL" "$@"
}

assert_json_schema() {
  local problems
  problems=$(json schema "$1") || {
    echo "schema violation: $problems"
    echo "$output"
    return 1
  }
}

assert_error() {
  local code=$1 exit_code=${2:-1}
  assert_json_schema error || return 1
  if [ "$status" -ne "$exit_code" ] || [ "$(json get error.code)" != "$code" ]; then
    echo "expected $code exit $exit_code, got exit $status: $output"
    return 1
  fi
}

# Runs a scan and stores its token in TOKEN.
scan_for_token() {
  run_cleanup scan "$@"
  [ "$status" -eq 0 ] || { echo "scan failed: $output"; return 1; }
  TOKEN=$(json get token)
}

clean_categories() {
  local categories=$1
  shift
  run_cleanup clean --token "$TOKEN" --categories "$categories" "$@"
}

assert_exists() {
  [ -e "$1" ] || [ -L "$1" ] || { echo "missing: $1"; return 1; }
}

assert_missing() {
  if [ -e "$1" ] || [ -L "$1" ]; then echo "still present: $1"; return 1; fi
}

# No fixture names, sandbox paths, user or host names may reach stdout.
assert_private() {
  local needle
  json strings-clean || { echo "path-like string in: $output"; return 1; }
  for needle in "$SANDBOX" "$SANDBOX_MARKER" "$(id -un)" "$(hostname -s)" "$@"; do
    [ "${#needle}" -ge 4 ] || continue
    case "$output" in
      *"$needle"*) echo "leaked '$needle' in: $output"; return 1 ;;
    esac
  done
}

snapshot_tree() {
  find "$SANDBOX_HOME" "$SANDBOX_TMP" "$OUTSIDE" -path "$STATE_DIR" -prune -o -print | sort
}

make_chrome_profile() {
  local profile=${1:-Default}
  CHROME_CACHE="$SANDBOX_HOME/Library/Caches/Google/Chrome/$profile"
  CHROME_DATA="$SANDBOX_HOME/Library/Application Support/Google/Chrome/$profile"
  make_file "$CHROME_CACHE/Cache/Cache_Data/blob-one" 8
  make_file "$CHROME_CACHE/Code Cache/js/blob-two" 8
  make_file "$CHROME_DATA/GPUCache/blob-three" 4
  make_file "$CHROME_DATA/Cookies" 4
  make_file "$CHROME_DATA/History" 4
  make_file "$CHROME_DATA/Login Data" 4
  make_file "$CHROME_DATA/Bookmarks" 4
  make_file "$CHROME_DATA/Sessions/session-file" 4
  make_file "$CHROME_DATA/Extensions/ext-id/manifest.json" 4
  make_file "$CHROME_DATA/Service Worker/CacheStorage/sw-blob" 4
}

# make_project DIR IDLE_DAYS [LOCKFILE]: node project idle for IDLE_DAYS.
make_project() {
  local dir=$1 idle_days=$2 lockfile=${3:-package-lock.json}
  make_file "$dir/package.json" 1
  [ "$lockfile" = none ] || make_file "$dir/$lockfile" 1
  make_file "$dir/src/index.js" 1
  make_file "$dir/node_modules/left-pad/index.js" 16
  age_tree "$dir" "$idle_days"
}
