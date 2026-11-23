#!/bin/bash
# node-modules-stale: finds node_modules folders of projects nobody touched.

readonly NODE_MODULES="node_modules"
readonly LOCKFILES=("package-lock.json" "yarn.lock" "pnpm-lock.yaml" "bun.lock" "bun.lockb")
readonly BUCKET_FLOORS=(30 90 180)
readonly BUCKET_IDS=("30-90" "90-180" "180+")
readonly KIBIBYTE=1024
readonly APPLICATIONS_FOLDER="Applications"
readonly APP_BUNDLE_PATTERN="*.app"
readonly GLOBAL_LINK_DEPTH=2

STALE_PATHS=()
STALE_IDLE=()
LINKED_PROJECTS=()

project_has_manifests() {
  local lockfile
  [ -f "$1/package.json" ] || return 1
  for lockfile in "${LOCKFILES[@]}"; do
    [ -f "$1/$lockfile" ] && return 0
  done
  return 1
}

# Newest modification time (epoch) of the project outside node_modules and
# .git internals, plus .git/index and .git/HEAD. Directories count too, so a
# deleted or added file is activity as well. Fails if any part is unreadable.
project_newest_mtime() {
  local project=$1
  {
    find -P "$project" -xdev \( -name "$NODE_MODULES" -o -name .git \) -prune \
      -o -exec stat -f '%m' {} + || echo unreadable
    stat -f '%m' "$project/.git/index" "$project/.git/HEAD"
  } 2> /dev/null | awk '
    $1 == "unreadable" { failed = 1 }
    $1 + 0 > newest { newest = $1 + 0 }
    END { if (failed || newest == 0) exit 1; printf "%.0f", newest }'
}

# Quick exit for active projects: stops at the first recently changed entry.
project_has_recent_change() {
  local found
  found=$(find -P "$1" -xdev \( -name "$NODE_MODULES" -o -name .git \) -prune \
    -o -mtime "-$((BUCKET_FLOORS[0] - 1))" -print -quit 2> /dev/null)
  [ -n "$found" ]
}

# Fills LINKED_PROJECTS with the projects that "npm link" exposed as global
# commands: symlinks in the global npm root (scoped packages sit one deeper).
# Their node_modules are what those commands run on.
load_linked_projects() {
  local root link target
  LINKED_PROJECTS=()
  tool_present npm || return 0
  root=$(run_tool "$TOOL_PROBE_SECONDS" npm root -g) || return 0
  case "$root" in /*) ;; *) return 0 ;; esac
  has_newline "$root" && return 0
  [ -d "$root" ] || return 0
  while IFS= read -r -d '' link; do
    target=$(physical_dir "$link") || continue
    LINKED_PROJECTS+=("$target")
  done < <(find -P "$root" -mindepth 1 -maxdepth "$GLOBAL_LINK_DEPTH" -type l -print0 2> /dev/null)
}

# Installed apps ship node_modules next to a package.json and a lockfile too;
# removing those breaks the app instead of an idle project.
project_is_excluded() {
  local project=$1 linked verdict=1
  shopt -s nocasematch
  case "$project/" in
    "$HOME_PHYS/$APPLICATIONS_FOLDER"/* | */$APP_BUNDLE_PATTERN/*) verdict=0 ;;
  esac
  shopt -u nocasematch
  [ "${#LINKED_PROJECTS[@]}" -gt 0 ] || return "$verdict"
  for linked in "${LINKED_PROJECTS[@]}"; do
    [ "$project" != "$linked" ] || verdict=0
  done
  return "$verdict"
}

# Fills STALE_PATHS / STALE_IDLE with every qualifying node_modules below ROOT
# whose project has been idle for at least the smallest bucket.
collect_stale_node_modules() {
  local root=$1 now candidate project newest idle
  STALE_PATHS=()
  STALE_IDLE=()
  now=$(date +%s)
  load_linked_projects
  while IFS= read -r -d '' candidate; do
    project=${candidate%/*}
    project_is_excluded "$project" && continue
    project_has_manifests "$project" || continue
    project_has_recent_change "$project" && continue
    newest=$(project_newest_mtime "$project") || continue
    is_uint "$newest" && [ "$newest" -le "$now" ] || continue
    idle=$(((now - newest) / SECONDS_PER_DAY))
    [ "$idle" -ge "${BUCKET_FLOORS[0]}" ] || continue
    STALE_PATHS+=("$candidate")
    STALE_IDLE+=("$idle")
  done < <(find -P "$root" -xdev -mindepth 1 \
    \( -name '.*' -o -name Library -o -name AppData -o -name "$APP_BUNDLE_PATTERN" \) -prune \
    -o -name "$NODE_MODULES" -prune -type d -print0 2> /dev/null)
}

tree_bytes() {
  du -skx -- "$1" 2> /dev/null | awk -v unit="$KIBIBYTE" 'NR == 1 { printf "%.0f", $1 * unit }'
}

bucket_index() {
  local idle=$1 index=0 position
  for position in 1 2; do
    [ "$idle" -ge "${BUCKET_FLOORS[$position]}" ] && index=$position
  done
  printf '%s' "$index"
}

buckets_json() {
  local position separator=""
  printf ',"buckets":['
  for position in 0 1 2; do
    printf '%s{"id":"%s","min_idle_days":%s,"project_count":%s,"size_bytes":%s}' "$separator" \
      "${BUCKET_IDS[$position]}" "${BUCKET_FLOORS[$position]}" "${BUCKET_COUNTS[$position]}" "${BUCKET_BYTES[$position]}"
    separator=","
  done
  printf ']'
}

projects_root() {
  if [ -n "$OPT_PROJECTS_DIR" ]; then printf '%s' "$OPT_PROJECTS_DIR"; else printf '%s' "$HOME_PHYS"; fi
}

# shellcheck disable=SC2034 # R_* are read by json_scan_category in output.sh
scan_projects() {
  local root position bytes index total=0
  BUCKET_COUNTS=(0 0 0)
  BUCKET_BYTES=(0 0 0)
  root=$(projects_root)
  if ! can_list "$root"; then
    R_STATUS=skipped_no_permission
    R_EXTRA=$(buckets_json)
    return 0
  fi
  collect_stale_node_modules "$root"
  position=0
  while [ "$position" -lt "${#STALE_PATHS[@]}" ]; do
    bytes=$(tree_bytes "${STALE_PATHS[$position]}")
    is_uint "$bytes" || bytes=0
    index=$(bucket_index "${STALE_IDLE[$position]}")
    BUCKET_COUNTS[index]=$((BUCKET_COUNTS[index] + 1))
    BUCKET_BYTES[index]=$((BUCKET_BYTES[index] + bytes))
    total=$((total + bytes))
    position=$((position + 1))
  done
  R_SIZE=$total
  R_COUNT=${#STALE_PATHS[@]}
  R_STATUS=empty
  [ "$R_COUNT" -gt 0 ] && R_STATUS=ok
  R_EXTRA=$(buckets_json)
}

# Removes one node_modules tree and adds what actually went away to R_FREED.
# Returns 1 when something of it is left behind.
remove_node_modules() {
  local path=$1 before after=0
  before=$(tree_bytes "$path")
  is_uint "$before" || before=0
  guarded_delete tree "$path"
  [ ! -e "$path" ] || after=$(tree_bytes "$path")
  is_uint "$after" || after=$before
  R_FREED=$((R_FREED + (before > after ? before - after : 0)))
  [ ! -e "$path" ]
}

clean_projects() {
  local position=0 removed=0 kept=0
  collect_stale_node_modules "$(projects_root)"
  while [ "$position" -lt "${#STALE_PATHS[@]}" ]; do
    if [ "${STALE_IDLE[$position]}" -ge "$OPT_MIN_IDLE" ]; then
      if remove_node_modules "${STALE_PATHS[$position]}"; then
        removed=$((removed + 1))
      else
        kept=$((kept + 1))
      fi
    fi
    position=$((position + 1))
  done
  if [ "$kept" -gt 0 ] && [ "$R_FREED" -gt 0 ]; then
    set_result partial SOME_ITEMS_REMAIN
  elif [ "$kept" -gt 0 ]; then
    set_result skipped_no_permission PERMISSION_DENIED
  elif [ "$removed" -gt 0 ]; then
    set_result cleaned
  else
    set_result not_found NOT_FOUND
  fi
}
