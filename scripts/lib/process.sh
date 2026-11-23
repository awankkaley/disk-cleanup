#!/bin/bash
# Process inspection and external tool execution.

readonly PLIST_READER="/usr/libexec/PlistBuddy"
readonly APP_PROCESS_PATTERN='\.app/Contents/'
readonly TOOL_POLL_SECONDS="0.1"
readonly TOOL_POLLS_PER_SECOND=10
readonly EXIT_TIMED_OUT=124

RUNNING_APPS_LOADED=0
RUNNING_APP_KEYS=()

# The only place that looks at running processes (tests stub pgrep on PATH).
query_processes() {
  case "$1" in
    exact) pgrep -x -- "$2" > /dev/null 2>&1 ;;
    full) pgrep -f -- "$2" > /dev/null 2>&1 ;;
    list) pgrep -lf -- "$2" 2> /dev/null ;;
    *) return 1 ;;
  esac
}

# CAT_PROCESS is "x:<process name>", "f:<command line pattern>" or "-".
category_is_running() {
  case "$CAT_PROCESS" in
    x:*) query_processes exact "${CAT_PROCESS#x:}" ;;
    f:*) query_processes full "${CAT_PROCESS#f:}" ;;
    *) return 1 ;;
  esac
}

# Collects the bundle name and bundle id of every running .app once per run.
load_running_apps() {
  local line bundle name bundle_id seen=$'\n'
  [ "$RUNNING_APPS_LOADED" = 0 ] || return 0
  RUNNING_APPS_LOADED=1
  while IFS= read -r line; do
    line=${line#* }
    case "$line" in /*.app/*) ;; *) continue ;; esac
    bundle="${line%%.app/*}.app"
    case "$seen" in *$'\n'"$bundle"$'\n'*) continue ;; esac
    seen="$seen$bundle"$'\n'
    name=${bundle##*/}
    RUNNING_APP_KEYS+=("${name%.app}")
    bundle_id=$("$PLIST_READER" -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist" 2> /dev/null) || continue
    [ -z "$bundle_id" ] || RUNNING_APP_KEYS+=("$bundle_id")
  done < <(query_processes list "$APP_PROCESS_PATTERN")
}

# True when a cache folder is named after a running app or its bundle id.
cache_owner_is_running() {
  local folder=$1 key verdict=1
  [ "${#RUNNING_APP_KEYS[@]}" -gt 0 ] || return 1
  shopt -s nocasematch
  for key in "${RUNNING_APP_KEYS[@]}"; do
    case "$folder" in "$key" | "$key".*) verdict=0 ;; esac
  done
  shopt -u nocasematch
  return "$verdict"
}

developer_dir_present() {
  command -v xcode-select > /dev/null 2>&1 && xcode-select -p > /dev/null 2>&1
}

# /usr/bin/pip3 and /usr/bin/xcrun are shims that open an "install developer
# tools" dialog when none are installed, so they only count when a developer
# directory is configured.
tool_present() {
  local location
  location=$(command -v "$1" 2> /dev/null) || return 1
  case "$location" in
    /usr/bin/pip3 | /usr/bin/xcrun) developer_dir_present ;;
  esac
}

# run_tool SECONDS COMMAND...: stdout passes through, stderr is dropped, and a
# tool that hangs (docker with a stuck daemon) is stopped after SECONDS.
run_tool() {
  local limit=$(($1 * TOOL_POLLS_PER_SECOND)) polls=0 pid
  shift
  (cd "$STATE_DIR" 2> /dev/null && exec "$@") < /dev/null 2> /dev/null &
  pid=$!
  while kill -0 "$pid" 2> /dev/null; do
    if [ "$polls" -ge "$limit" ]; then
      kill "$pid" 2> /dev/null
      wait "$pid" 2> /dev/null
      return "$EXIT_TIMED_OUT"
    fi
    sleep "$TOOL_POLL_SECONDS"
    polls=$((polls + 1))
  done
  wait "$pid"
}
