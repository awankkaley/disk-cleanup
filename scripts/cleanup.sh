#!/bin/bash
# disk-cleanup (macOS): frees disk space and reports aggregated JSON only.
# Runs on the stock /bin/bash 3.2 with tools that ship with macOS.

set -u
export LC_ALL=C

readonly VERSION="1.1.0"
readonly SCHEMA_VERSION=1
readonly PLATFORM="macos"
readonly EXIT_ERROR=1
readonly EXIT_USAGE=2
readonly TOKEN_TTL_SECONDS=900
readonly SECONDS_PER_DAY=86400
readonly DEFAULT_MIN_AGE_DAYS=7
readonly MIN_AGE_DAYS_FLOOR=1
readonly DEFAULT_MIN_IDLE_DAYS=30
readonly MIN_IDLE_DAYS_FLOOR=30
readonly MAX_DAYS=36500
readonly MAX_DAY_DIGITS=5
readonly DEEP_ONLY_CATEGORY="node-modules-stale"
readonly TRASH_CATEGORY="trash"
readonly TRASH_FLAG="--empty-trash"

OPT_DEEP=0
OPT_MIN_AGE=$DEFAULT_MIN_AGE_DAYS
OPT_PROJECTS_DIR=""
OPT_TOKEN=""
OPT_EMPTY_TRASH=0
OPT_MIN_IDLE=$DEFAULT_MIN_IDLE_DAYS
OPT_LOG=0

# Directory of this file after following symlinks, so lib/ is found when the
# script is linked into a PATH directory.
parent_path() {
  case "$1" in
    /*/*) printf '%s' "${1%/*}" ;;
    /*) printf '/' ;;
    */*) printf '%s' "${1%/*}" ;;
    *) printf '.' ;;
  esac
}

resolve_script_dir() {
  local script=${BASH_SOURCE[0]} directory link
  while [ -L "$script" ]; do
    directory=$(cd -P "$(parent_path "$script")" 2> /dev/null && pwd) || return 1
    link=$(readlink "$script") || return 1
    case "$link" in
      /*) script=$link ;;
      *) script="$directory/$link" ;;
    esac
  done
  cd -P "$(parent_path "$script")" 2> /dev/null && pwd
}

SCRIPT_DIR=$(resolve_script_dir) || SCRIPT_DIR=""
if [ ! -r "$SCRIPT_DIR/lib/output.sh" ]; then
  printf '{"schema_version":1,"error":{"code":"INTERNAL","message":"The script could not run safely in this environment."}}\n'
  exit 1
fi
# shellcheck source=scripts/lib/output.sh
source "$SCRIPT_DIR/lib/output.sh"
# shellcheck source=scripts/lib/guard.sh
source "$SCRIPT_DIR/lib/guard.sh"
# shellcheck source=scripts/lib/process.sh
source "$SCRIPT_DIR/lib/process.sh"
# shellcheck source=scripts/lib/catalog.sh
source "$SCRIPT_DIR/lib/catalog.sh"
# shellcheck source=scripts/lib/tools.sh
source "$SCRIPT_DIR/lib/tools.sh"
# shellcheck source=scripts/lib/state.sh
source "$SCRIPT_DIR/lib/state.sh"
# shellcheck source=scripts/lib/projects.sh
source "$SCRIPT_DIR/lib/projects.sh"
# shellcheck source=scripts/lib/scan.sh
source "$SCRIPT_DIR/lib/scan.sh"
# shellcheck source=scripts/lib/clean.sh
source "$SCRIPT_DIR/lib/clean.sh"

# is_day_count VALUE FLOOR
is_day_count() {
  is_uint "${1:-}" && [ "${#1}" -le "$MAX_DAY_DIGITS" ] || return 1
  [ "$((10#$1))" -ge "$2" ] && [ "$((10#$1))" -le "$MAX_DAYS" ]
}

# The walk root must be a real folder inside HOME and outside everything the
# walk itself refuses to enter.
projects_dir_is_acceptable() {
  local relative
  has_newline "$1" && return 1
  is_real_dir "$1" && path_is_under "$1" "$HOME_PHYS" || return 1
  relative=${1#"$HOME_PHYS"}
  case "$relative/" in
    */.* | */Library/* | */AppData/* | */node_modules/*) return 1 ;;
  esac
  return 0
}

resolve_projects_dir() {
  local physical
  [ -n "$OPT_PROJECTS_DIR" ] || return 0
  physical=$(physical_dir "$OPT_PROJECTS_DIR") || fail INVALID_ARGUMENT
  projects_dir_is_acceptable "$physical" || fail INVALID_ARGUMENT
  OPT_PROJECTS_DIR=$physical
}

parse_scan_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --deep) OPT_DEEP=1 ;;
      --min-age-days)
        [ $# -ge 2 ] || fail USAGE
        is_day_count "$2" "$MIN_AGE_DAYS_FLOOR" || fail INVALID_ARGUMENT
        OPT_MIN_AGE=$((10#$2))
        shift
        ;;
      --projects-dir)
        [ $# -ge 2 ] || fail USAGE
        [ -n "$2" ] || fail INVALID_ARGUMENT
        OPT_PROJECTS_DIR=$2
        shift
        ;;
      *) fail USAGE ;;
    esac
    shift
  done
}

parse_clean_args() {
  local categories=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --empty-trash) OPT_EMPTY_TRASH=1 ;;
      --log) OPT_LOG=1 ;;
      --token | --categories | --min-idle-days)
        [ $# -ge 2 ] || fail USAGE
        case "$1" in
          --token) OPT_TOKEN=$2 ;;
          --categories) categories=$2 ;;
          --min-idle-days)
            is_day_count "$2" "$MIN_IDLE_DAYS_FLOOR" || fail INVALID_ARGUMENT
            OPT_MIN_IDLE=$((10#$2))
            ;;
        esac
        shift
        ;;
      *) fail USAGE ;;
    esac
    shift
  done
  [ -n "$categories" ] || fail USAGE
  parse_categories "$categories"
}

main() {
  local action=${1:-}
  exec 2> /dev/null
  trap emit_error_if_silent EXIT
  [ $# -ge 1 ] || fail USAGE
  shift
  case "$action" in
    --help | -h) emit_help ;;
    --version) emit_version ;;
    scan)
      parse_scan_args "$@"
      init_environment
      resolve_projects_dir
      run_scan
      ;;
    clean)
      parse_clean_args "$@"
      init_environment
      run_clean
      ;;
    *) fail USAGE ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
