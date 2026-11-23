#!/bin/bash
# The fixed category list and how each category finds its folders.

readonly DEVICE_SUPPORT_STALE_DAYS=90

# id|group|risk|kind|process|label|impact  (all strings are static constants)
readonly CATEGORY_ROWS=(
  "app-caches|system|safe|dirs|-|Application caches|Apps rebuild their caches automatically and may start slower once."
  "temp-files|system|safe|aged|-|Temporary files|Only temporary files older than the age threshold are removed."
  "logs|system|safe|aged|-|Logs and crash reports|Old log files and diagnostic reports can no longer be consulted."
  "trash|system|irreversible|dirs|-|Trash|Everything in the Trash is deleted permanently and cannot be restored."
  "browser-chrome|browser|safe|dirs|x:Google Chrome|Chrome cache|Pages may load slightly slower once while the cache rebuilds."
  "browser-edge|browser|safe|dirs|x:Microsoft Edge|Edge cache|Pages may load slightly slower once while the cache rebuilds."
  "browser-firefox|browser|safe|dirs|x:firefox|Firefox cache|Pages may load slightly slower once while the cache rebuilds."
  "browser-brave|browser|safe|dirs|x:Brave Browser|Brave cache|Pages may load slightly slower once while the cache rebuilds."
  "browser-opera|browser|safe|dirs|x:Opera|Opera cache|Pages may load slightly slower once while the cache rebuilds."
  "browser-arc|browser|safe|dirs|x:Arc|Arc cache|Pages may load slightly slower once while the cache rebuilds."
  "browser-safari|browser|safe|dirs|x:Safari|Safari cache|Pages may load slightly slower once while the cache rebuilds."
  "npm-cache|developer|safe|tool|-|npm cache|Packages are downloaded again on the next install."
  "yarn-cache|developer|safe|tool|-|Yarn cache|Packages are downloaded again on the next install."
  "pnpm-store|developer|safe|tool|-|pnpm store|Only packages no project references are removed, so the amount freed is known only after cleaning."
  "pip-cache|developer|safe|tool|-|pip cache|Packages are downloaded again on the next install."
  "gradle-cache|developer|safe|dirs|f:GradleDaemon|Gradle cache|Dependencies are downloaded again on the next build."
  "cargo-cache|developer|safe|dirs|-|Cargo registry cache|Crates are downloaded and unpacked again on the next build."
  "go-cache|developer|safe|tool|-|Go build cache|The next Go build compiles everything again once."
  "docker-dangling|developer|safe|docker|-|Dangling Docker images|Only untagged images that nothing uses are removed."
  "homebrew-cache|developer|safe|tool|-|Homebrew cache|Old downloads and outdated package versions are removed."
  "cocoapods-cache|developer|safe|dirs|-|CocoaPods cache|Pods are downloaded again on the next install."
  "xcode-derived-data|developer|safe|dirs|x:Xcode|Xcode derived data|The next build of each project is a full build and indexing runs again."
  "xcode-device-support|developer|safe|subdirs|-|Xcode device support files|Support files are copied again when such a device is connected."
  "xcode-simulators-unavailable|developer|safe|simulators|-|Unavailable Xcode simulators|Only simulators the installed Xcode can no longer run are removed."
  "node-modules-stale|projects|rebuild_needed|projects|-|Dependencies of idle projects|Run the package manager install again before working on those projects."
)
# Top-level cache folders that belong to another category, or that hold
# downloads which are expensive to restore (browser binaries, virtualenvs).
readonly APP_CACHES_EXCLUDED=(
  "Google" "Microsoft Edge" "Firefox" "BraveSoftware" "com.operasoftware.Opera"
  "Arc" "com.apple.Safari" "Homebrew" "CocoaPods" "pip" "Yarn" "go-build"
  "ms-playwright" "pypoetry" "Cypress"
)
# Caches of system services: their owners are always running, so the
# running-app rule keeps them out for good.
readonly APP_CACHES_EXCLUDED_PREFIX="com.apple."
readonly APP_CACHES_EXCLUDED_SYSTEM=("CloudKit" "FamilyCircle" "GeoServices" "PassKit" "GameKit")
readonly CHROMIUM_CACHE_NAMES=("Cache" "Code Cache" "GPUCache")
readonly SAFARI_CACHE_NAMES=("WebKitCache" "fsCachedData")

TARGETS=()
TARGETS_DENIED=0

# shellcheck disable=SC2034 # CAT_* are read by the scan, clean and output files
category_lookup() {
  local row rest
  for row in "${CATEGORY_ROWS[@]}"; do
    [ "${row%%|*}" = "$1" ] || continue
    CAT_ID=$1
    rest=${row#*|}
    CAT_GROUP=${rest%%|*} rest=${rest#*|}
    CAT_RISK=${rest%%|*} rest=${rest#*|}
    CAT_KIND=${rest%%|*} rest=${rest#*|}
    CAT_PROCESS=${rest%%|*} rest=${rest#*|}
    CAT_LABEL=${rest%%|*}
    CAT_IMPACT=${rest#*|}
    return 0
  done
  return 1
}

list_contains() {
  local wanted=$1 item verdict=1
  shift
  shopt -s nocasematch
  for item in "$@"; do
    case "$wanted" in "$item") verdict=0 ;; esac
  done
  shopt -u nocasematch
  return "$verdict"
}

is_real_dir() {
  [ -d "$1" ] && [ ! -L "$1" ]
}

add_dir() {
  is_real_dir "$1" || return 0
  if can_list "$1"; then TARGETS+=("$1"); else TARGETS_DENIED=1; fi
}

# add_named_dirs MIN MAX BASE NAME...: directories called NAME found between
# MIN and MAX levels below BASE.
add_named_dirs() {
  local min=$1 max=$2 base=$3 name found
  local matcher=()
  shift 3
  is_real_dir "$base" || return 0
  can_list "$base" || { TARGETS_DENIED=1; return 0; }
  for name in "$@"; do
    [ "${#matcher[@]}" -eq 0 ] || matcher+=(-o)
    matcher+=(-name "$name")
  done
  while IFS= read -r -d '' found; do
    TARGETS+=("$found")
  done < <(find -P "$base" -xdev -mindepth "$min" -maxdepth "$max" -type d \
    \( "${matcher[@]}" \) -print0 2> /dev/null)
}

add_chromium() {
  add_named_dirs 1 2 "$LIBRARY/Caches/$1" "${CHROMIUM_CACHE_NAMES[@]}"
  add_named_dirs 1 2 "$LIBRARY/Application Support/$1" "${CHROMIUM_CACHE_NAMES[@]}"
}

add_firefox() {
  add_named_dirs 2 2 "$LIBRARY/Caches/Firefox/Profiles" "cache2" "startupCache"
  add_named_dirs 2 2 "$LIBRARY/Application Support/Firefox/Profiles" "startupCache"
}

add_safari() {
  local container="$LIBRARY/Containers/com.apple.Safari"
  add_named_dirs 1 1 "$LIBRARY/Caches/com.apple.Safari" "${SAFARI_CACHE_NAMES[@]}"
  is_real_dir "$container" || return 0
  can_list "$container" || { TARGETS_DENIED=1; return 0; }
  is_real_dir "$container/Data" || return 0
  if can_list "$container/Data"; then
    add_named_dirs 1 2 "$container/Data/Library/Caches" "${SAFARI_CACHE_NAMES[@]}"
  else
    TARGETS_DENIED=1
  fi
}

add_app_caches() {
  local root="$LIBRARY/Caches" entry name
  is_real_dir "$root" || return 0
  can_list "$root" || { TARGETS_DENIED=1; return 0; }
  load_running_apps
  while IFS= read -r -d '' entry; do
    name=${entry##*/}
    case "$name" in "$APP_CACHES_EXCLUDED_PREFIX"*) continue ;; esac
    list_contains "$name" "${APP_CACHES_EXCLUDED[@]}" "${APP_CACHES_EXCLUDED_SYSTEM[@]}" && continue
    cache_owner_is_running "$name" && continue
    TARGETS+=("$entry")
  done < <(find -P "$root" -xdev -mindepth 1 -maxdepth 1 -type d -print0 2> /dev/null)
}

add_stale_subdirs() {
  local base=$1 days=$2 found
  is_real_dir "$base" || return 0
  can_list "$base" || { TARGETS_DENIED=1; return 0; }
  while IFS= read -r -d '' found; do
    TARGETS+=("$found")
  done < <(find -P "$base" -xdev -mindepth 1 -maxdepth 1 -type d -mtime "+$days" -print0 2> /dev/null)
}

# Fills TARGETS with the folders a category owns (re-resolved on every run).
# shellcheck disable=SC2034 # TARGETS_DENIED is read by scan.sh and clean.sh
resolve_targets() {
  TARGETS=()
  TARGETS_DENIED=0
  case "$1" in
    app-caches) add_app_caches ;;
    trash) add_dir "$HOME_PHYS/$TRASH_NAME" ;;
    browser-chrome) add_chromium "Google/Chrome" ;;
    browser-edge) add_chromium "Microsoft Edge" ;;
    browser-brave) add_chromium "BraveSoftware/Brave-Browser" ;;
    browser-opera) add_chromium "com.operasoftware.Opera" ;;
    browser-arc) add_chromium "Arc/User Data" ;;
    browser-firefox) add_firefox ;;
    browser-safari) add_safari ;;
    npm-cache) add_dir "$HOME_PHYS/.npm/_cacache" ;;
    yarn-cache) add_dir "$LIBRARY/Caches/Yarn"; add_dir "$HOME_PHYS/.yarn/berry/cache" ;;
    pnpm-store) add_dir "$LIBRARY/pnpm/store" ;;
    pip-cache) add_dir "$LIBRARY/Caches/pip" ;;
    gradle-cache) add_dir "$HOME_PHYS/.gradle/caches" ;;
    cargo-cache) add_dir "$HOME_PHYS/.cargo/registry/cache"; add_dir "$HOME_PHYS/.cargo/registry/src" ;;
    go-cache) add_dir "$LIBRARY/Caches/go-build" ;;
    homebrew-cache) add_dir "$LIBRARY/Caches/Homebrew" ;;
    cocoapods-cache) add_dir "$LIBRARY/Caches/CocoaPods" ;;
    xcode-derived-data) add_dir "$LIBRARY/Developer/Xcode/DerivedData" ;;
    xcode-device-support)
      add_stale_subdirs "$LIBRARY/Developer/Xcode/iOS DeviceSupport" "$DEVICE_SUPPORT_STALE_DAYS"
      ;;
    xcode-simulators-unavailable) add_dir "$LIBRARY/Developer/CoreSimulator/Devices" ;;
  esac
}
