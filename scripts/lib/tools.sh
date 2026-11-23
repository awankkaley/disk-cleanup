#!/bin/bash
# Developer tools that have an official cleaning command. Such a command
# deletes wherever the tool's own configuration points, which the guard never
# sees, so it may only run after the tool has told us where that is.

readonly TOOL_PROBE_SECONDS=10

# shellcheck disable=SC2034 # the TOOL_* results are read by scan.sh and clean.sh
TOOL_COMMAND=()
TOOL_LOCATE=()
TOOL_DEFAULT=""
TOOL_SUBDIR=""
TOOL_HAS_FALLBACK=0
TOOL_SIZE_KNOWN=1
TOOL_PLAN=""

# Sets, for one category: TOOL_COMMAND (the official cleaning command),
# TOOL_LOCATE (prints the tool's cache folder), TOOL_DEFAULT (where that folder
# is when nothing was reconfigured; TOOL_SUBDIR is the part of it the command
# empties), and whether the guarded delete of the default folder may stand in.
# shellcheck disable=SC2034 # read by scan.sh and clean.sh
category_tool() {
  TOOL_HAS_FALLBACK=1
  TOOL_SIZE_KNOWN=1
  TOOL_SUBDIR=""
  case "$1" in
    npm-cache)
      TOOL_COMMAND=(npm cache clean --force) TOOL_LOCATE=(npm config get cache)
      TOOL_SUBDIR="/_cacache" TOOL_DEFAULT="$HOME_PHYS/.npm$TOOL_SUBDIR"
      ;;
    yarn-cache)
      TOOL_COMMAND=(yarn cache clean) TOOL_LOCATE=(yarn cache dir)
      TOOL_DEFAULT="$LIBRARY/Caches/Yarn"
      ;;
    pnpm-store)
      TOOL_COMMAND=(pnpm store prune) TOOL_LOCATE=(pnpm store path)
      TOOL_DEFAULT="$LIBRARY/pnpm/store" TOOL_HAS_FALLBACK=0 TOOL_SIZE_KNOWN=0
      ;;
    pip-cache)
      TOOL_COMMAND=(pip3 cache purge) TOOL_LOCATE=(pip3 cache dir)
      tool_present pip3 || { TOOL_COMMAND=(pip cache purge) TOOL_LOCATE=(pip cache dir); }
      TOOL_DEFAULT="$LIBRARY/Caches/pip"
      ;;
    go-cache)
      TOOL_COMMAND=(go clean -cache) TOOL_LOCATE=(go env GOCACHE)
      TOOL_DEFAULT="$LIBRARY/Caches/go-build"
      ;;
    homebrew-cache)
      TOOL_COMMAND=(brew cleanup -s) TOOL_LOCATE=(brew --cache)
      TOOL_DEFAULT="$LIBRARY/Caches/Homebrew"
      ;;
    *) return 1 ;;
  esac
}

# Prints the one absolute path the tool answered with; fails on anything else.
tool_reported_dir() {
  local answer
  answer=$(run_tool "$TOOL_PROBE_SECONDS" "${TOOL_LOCATE[@]}") || return 1
  case "$answer" in /*) ;; *) return 1 ;; esac
  has_newline "$answer" && return 1
  printf '%s' "$answer"
}

# True when the folder the tool would empty, physically resolved, is at or
# under the catalog default and is a place the guarded delete would accept.
tool_location_is_default() {
  local location
  location=$(physical_path "$1$TOOL_SUBDIR") || return 1
  path_is_under "$location" "$TOOL_DEFAULT" || return 1
  [ ! -d "$location" ] || guard_resolve contents "$location" > /dev/null
}

fallback_delete_possible() {
  [ "$TOOL_HAS_FALLBACK" = 1 ] && [ "${#TARGETS[@]}" -gt 0 ]
}

# Decides, identically for scan and clean, what may happen to a tool category:
#   absent       nothing installed and no default folder to delete
#   command      the tool reported a default location: its command may run
#   custom       the tool keeps its cache elsewhere: nothing is run or deleted
#   delete       the tool cannot say where its cache is (or is not installed):
#                its command is not run; the default folder goes through the guard
#   unavailable  the tool cannot say where its cache is and no fallback exists
# shellcheck disable=SC2034 # TOOL_PLAN is read by scan.sh and clean.sh
tool_plan() {
  local reported
  category_tool "$1" || return 1
  resolve_targets "$1"
  TOOL_PLAN="absent"
  if ! tool_present "${TOOL_COMMAND[0]}"; then
    fallback_delete_possible && TOOL_PLAN="delete"
    return 0
  fi
  if reported=$(tool_reported_dir); then
    TOOL_PLAN="custom"
    tool_location_is_default "$reported" && TOOL_PLAN="command"
    return 0
  fi
  TOOL_PLAN="unavailable"
  fallback_delete_possible && TOOL_PLAN="delete"
  return 0
}
