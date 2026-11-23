#!/usr/bin/env bash
# Installs the disk-cleanup Agent Skill into the skills directory of each AI agent on this machine,
# plus /disk-cleanup command files for the agents that read user-level command files.
# Usage: install.sh [--agent NAME[,NAME...]] [--uninstall] [--local PATH] [--help]
set -eu

VERSION="v1.2.0"
REPO="awankkaley/disk-cleanup"
SKILL_NAME="disk-cleanup"
# A command file is ours only when it carries this marker line.
COMMAND_MARKER="disk-cleanup-skill:managed-command"
ARCHIVE_URL="https://github.com/${REPO}/archive/refs/tags/${VERSION}.tar.gz"
KNOWN_AGENTS="claude codex cursor gemini copilot opencode amp goose agents"
# One namespaced command per mode, next to the plain /disk-cleanup command.
COMMAND_MODES="scan scan-only review deep help"
EXIT_USAGE=2

MODE="install"
LOCAL_SOURCE=""
REQUESTED_AGENTS=""
TMP_DIR=""
SOURCE_DIR=""
DONE_DIRS=""

usage() {
  cat <<EOF
disk-cleanup skill installer (${VERSION})

Usage:
  install.sh [options]

Options:
  --agent NAME     Install only for this agent. Repeatable, or a comma list.
                   Names: ${KNOWN_AGENTS}
  --uninstall      Remove the skill instead of installing it.
  --local PATH     Install from a local checkout instead of downloading.
  --help           Show this help.

Without --agent, the skill is installed for every agent found on this machine.
Only the "${SKILL_NAME}" folder inside each agent's skills directory is written or removed,
and an existing folder of that name is only replaced or removed when it is this skill.

Gemini CLI and OpenCode also get small command files that only start the skill:
/${SKILL_NAME} plus one per mode in a "${SKILL_NAME}" subfolder (Gemini CLI shows
them as /${SKILL_NAME}:scan, :scan-only, :review, :deep, :help; OpenCode as /${SKILL_NAME}/scan
and so on), under ~/.gemini/commands/ and ~/.config/opencode/commands/. A file of
the same name that this installer did not write is never replaced or removed.
EOF
}

info() { printf '%s\n' "$*"; }
warn() { printf 'Warning: %s\n' "$*" >&2; }

die() {
  printf 'Error: %s\n' "$1" >&2
  exit "${2:-1}"
}

cleanup_tmp() {
  if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}

# Directory whose existence means the agent is installed.
agent_marker_dir() {
  case "$1" in
    claude) printf '%s' "$HOME/.claude" ;;
    codex) printf '%s' "$HOME/.codex" ;;
    cursor) printf '%s' "$HOME/.cursor" ;;
    gemini) printf '%s' "$HOME/.gemini" ;;
    copilot) printf '%s' "$HOME/.copilot" ;;
    opencode) printf '%s' "$HOME/.config/opencode" ;;
    amp) printf '%s' "$HOME/.config/amp" ;;
    goose) printf '%s' "$HOME/.config/goose" ;;
    agents) printf '%s' "$HOME/.agents" ;;
    *) return 1 ;;
  esac
}

# Codex, Amp and Goose read the shared ~/.agents/skills directory.
agent_skills_dir() {
  case "$1" in
    claude) printf '%s' "$HOME/.claude/skills" ;;
    cursor) printf '%s' "$HOME/.cursor/skills" ;;
    gemini) printf '%s' "$HOME/.gemini/skills" ;;
    copilot) printf '%s' "$HOME/.copilot/skills" ;;
    opencode) printf '%s' "$HOME/.config/opencode/skills" ;;
    codex | amp | goose | agents) printf '%s' "$HOME/.agents/skills" ;;
    *) return 1 ;;
  esac
}

# The agents that read user-level command files, and where. Empty for all others.
agent_commands_dir() {
  case "$1" in
    gemini) printf '%s' "$HOME/.gemini/commands" ;;
    opencode) printf '%s' "$HOME/.config/opencode/commands" ;;
    *) : ;;
  esac
}

agent_command_extension() {
  case "$1" in
    gemini) printf 'toml' ;;
    opencode) printf 'md' ;;
    *) : ;;
  esac
}

# Command files of an agent, one per line: the plain command, then one per mode
# in the namespace subfolder. The same relative path is used under
# commands/<agent>/ in the source and under the agent's commands directory.
agent_command_files() {
  local extension mode
  extension=$(agent_command_extension "$1")
  [ -n "$extension" ] || return 0
  printf '%s\n' "${SKILL_NAME}.${extension}"
  for mode in $COMMAND_MODES; do
    printf '%s\n' "${SKILL_NAME}/${mode}.${extension}"
  done
}

is_known_agent() {
  case " $KNOWN_AGENTS " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

add_requested_agents() {
  local list name
  list=$(printf '%s' "$1" | tr ',' ' ')
  [ -n "$list" ] || die "--agent needs a name. Known agents: $KNOWN_AGENTS" "$EXIT_USAGE"
  for name in $list; do
    is_known_agent "$name" || die "Unknown agent '$name'. Known agents: $KNOWN_AGENTS" "$EXIT_USAGE"
    REQUESTED_AGENTS="$REQUESTED_AGENTS $name"
  done
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --agent)
        [ $# -ge 2 ] || die "--agent needs a name. Known agents: $KNOWN_AGENTS" "$EXIT_USAGE"
        add_requested_agents "$2"
        shift 2
        ;;
      --agent=*)
        add_requested_agents "${1#--agent=}"
        shift
        ;;
      --local)
        [ $# -ge 2 ] || die "--local needs a path to a checkout." "$EXIT_USAGE"
        LOCAL_SOURCE="$2"
        shift 2
        ;;
      --local=*)
        LOCAL_SOURCE="${1#--local=}"
        shift
        ;;
      --uninstall)
        MODE="uninstall"
        shift
        ;;
      --help | -h)
        usage
        exit 0
        ;;
      *)
        die "Unknown option '$1'. Run with --help to see the options." "$EXIT_USAGE"
        ;;
    esac
  done
}

require_home() {
  case "${HOME:-}" in
    /*) [ -d "$HOME" ] || die "HOME does not point to an existing folder." ;;
    *) die "HOME is not set to an absolute path." ;;
  esac
}

warn_if_unsupported_os() {
  case "$(uname -s 2>/dev/null || printf 'unknown')" in
    Darwin | MINGW* | MSYS* | CYGWIN*) ;;
    *) warn "this skill only cleans macOS and Windows. It will be installed, but it cannot clean this system." ;;
  esac
}

detected_agents() {
  local name found=""
  for name in $KNOWN_AGENTS; do
    if [ -d "$(agent_marker_dir "$name")" ]; then
      found="$found $name"
    fi
  done
  printf '%s' "$found"
}

validate_source() {
  [ -f "$1/SKILL.md" ] || die "No SKILL.md found in the source. It does not look like a ${SKILL_NAME} checkout."
  [ -d "$1/scripts" ] || die "No scripts folder found in the source."
  [ -f "$1/LICENSE" ] || die "No LICENSE file found in the source."
}

download_source() {
  command -v curl >/dev/null 2>&1 || die "curl is required to download the skill."
  command -v tar >/dev/null 2>&1 || die "tar is required to unpack the skill."
  TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/${SKILL_NAME}-install.XXXXXX") || die "Could not create a temporary folder."
  info "Downloading ${SKILL_NAME} ${VERSION} ..."
  curl -fsSL "$ARCHIVE_URL" -o "$TMP_DIR/skill.tar.gz" ||
    die "Download failed. Check your internet connection, or use --local with a checkout."
  mkdir "$TMP_DIR/src"
  tar -xzf "$TMP_DIR/skill.tar.gz" -C "$TMP_DIR/src" --strip-components=1 ||
    die "Could not unpack the downloaded archive."
  SOURCE_DIR="$TMP_DIR/src"
}

# Physical form of a path whose tail may not exist yet.
physical_path() {
  local path="$1" tail=""
  while [ -n "$path" ] && [ ! -d "$path" ]; do
    tail="/${path##*/}$tail"
    case "$path" in
      */*) path="${path%/*}" ;;
      *) path="." ;;
    esac
  done
  path=$(cd -P "${path:-/}" 2>/dev/null && pwd -P) || return 1
  printf '%s%s' "${path%/}" "$tail"
}

paths_overlap() {
  [ "$1" = "$2" ] && return 0
  case "$1" in "$2"/*) return 0 ;; esac
  case "$2" in "$1"/*) return 0 ;; esac
  return 1
}

# True when the folder holds a SKILL.md whose frontmatter names this skill.
is_this_skill() {
  [ -f "$1/SKILL.md" ] || return 1
  awk -v wanted="$SKILL_NAME" '
    NR == 1 { if ($0 !~ /^---[ \t\r]*$/) exit; inside = 1; next }
    inside && /^---[ \t\r]*$/ { exit }
    inside && /^name:/ {
      value = $0
      sub(/^name:[ \t]*/, "", value)
      sub(/[ \t\r]+$/, "", value)
      gsub(/^["\047]|["\047]$/, "", value)
      if (value == wanted) found = 1
    }
    END { exit found ? 0 : 1 }' "$1/SKILL.md" 2>/dev/null
}

dir_is_empty() {
  [ -z "$(ls -A "$1" 2>/dev/null)" ]
}

# Refuses, before anything is changed, an existing folder that is not this
# skill. A symlink is fine: only the link itself is ever removed.
require_own_destination() {
  local dest="$1"
  [ ! -L "$dest" ] || return 0
  [ -e "$dest" ] || return 0
  [ -d "$dest" ] || die "$dest exists and is not a folder. Nothing was changed; move or remove it yourself."
  is_this_skill "$dest" || dir_is_empty "$dest" ||
    die "$dest exists but is not this skill (no SKILL.md named ${SKILL_NAME}). Nothing was changed; move or remove it yourself."
}

# Replacing the destination deletes it first, so a source that is, contains or
# lies inside the destination would be deleted before it could be copied.
require_separate_source() {
  local dest="$1" physical
  physical=$(physical_path "$dest") || die "Could not resolve $dest"
  if paths_overlap "$SOURCE_DIR" "$physical"; then
    die "The --local source and the install destination $dest overlap. Nothing was changed; install from a separate checkout."
  fi
}

remove_destination() {
  local dest="$1"
  if [ -L "$dest" ]; then
    rm -f "$dest"
  elif [ -d "$dest" ]; then
    rm -rf "$dest"
  fi
}

# True for a regular file (never a symlink) that carries our marker line.
is_our_command() {
  [ ! -L "$1" ] && [ -f "$1" ] && grep -qF "$COMMAND_MARKER" "$1" 2>/dev/null
}

# Fails before anything is changed when the source lacks a command file that a
# requested agent needs, or ships one without the marker uninstall relies on.
check_command_sources() {
  local name relative
  for name in $1; do
    for relative in $(agent_command_files "$name"); do
      is_our_command "$SOURCE_DIR/commands/$name/$relative" ||
        die "The source has no valid commands/$name/$relative. It does not look like a ${SKILL_NAME} ${VERSION} checkout."
    done
  done
}

# install_command_file AGENT SOURCE DEST. A command file that is not ours is the
# user's own: it is skipped, never replaced.
install_command_file() {
  local agent="$1" source="$2" dest="$3"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if ! is_our_command "$dest"; then
      info "  skipped    $dest already exists and was not written by this installer; left untouched."
      info "             The skill is installed, but that command stays your own for $agent."
      return 0
    fi
  fi
  if ! mkdir -p "${dest%/*}" 2>/dev/null || ! cp "$source" "$dest" 2>/dev/null; then
    warn "could not write $dest. The skill is installed, but that command is not available for $agent."
    return 0
  fi
  info "  installed  $dest"
}

# The namespace subfolder is only used when it is a real folder: nothing is
# written or removed through a symlink the user put there.
install_command() {
  local commands_dir relative
  commands_dir=$(agent_commands_dir "$1")
  [ -n "$commands_dir" ] || return 0
  for relative in $(agent_command_files "$1"); do
    case "$relative" in
      */*)
        if [ -L "$commands_dir/$SKILL_NAME" ]; then
          info "  skipped    $commands_dir/$relative: the ${SKILL_NAME} folder there is a link; left untouched."
          continue
        fi
        ;;
    esac
    install_command_file "$1" "$SOURCE_DIR/commands/$1/$relative" "$commands_dir/$relative"
  done
}

uninstall_command_file() {
  local dest="$1"
  if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
    return 0
  fi
  if ! is_our_command "$dest"; then
    info "  kept       $dest was not written by this installer; left untouched."
    return 0
  fi
  rm -f "$dest" || die "Could not remove $dest"
  info "  removed    $dest"
}

# Removes our command files, then the namespace subfolder when nothing is left in it.
uninstall_command() {
  local commands_dir relative namespace_dir
  commands_dir=$(agent_commands_dir "$1")
  [ -n "$commands_dir" ] || return 0
  namespace_dir="$commands_dir/$SKILL_NAME"
  for relative in $(agent_command_files "$1"); do
    case "$relative" in
      */*) [ ! -L "$namespace_dir" ] || continue ;;
    esac
    uninstall_command_file "$commands_dir/$relative"
  done
  if [ ! -L "$namespace_dir" ] && [ -d "$namespace_dir" ] && dir_is_empty "$namespace_dir"; then
    rmdir "$namespace_dir" 2>/dev/null || :
  fi
}

resolve_source() {
  if [ -n "$LOCAL_SOURCE" ]; then
    [ -d "$LOCAL_SOURCE" ] || die "--local path is not a folder."
    SOURCE_DIR=$(cd "$LOCAL_SOURCE" && pwd -P)
  else
    download_source
  fi
  validate_source "$SOURCE_DIR"
}

already_done() {
  case "$DONE_DIRS" in
    *"|$1|"*) return 0 ;;
    *) return 1 ;;
  esac
}

install_into() {
  local skills_dir="$1" dest="$1/$SKILL_NAME"
  mkdir -p "$skills_dir" || die "Could not create $skills_dir"
  remove_destination "$dest" || die "Could not replace $dest"
  mkdir "$dest" || die "Could not create $dest"
  cp "$SOURCE_DIR/SKILL.md" "$SOURCE_DIR/LICENSE" "$dest/" || die "Could not copy files into $dest"
  cp -R "$SOURCE_DIR/scripts" "$dest/scripts" || die "Could not copy scripts into $dest"
  info "  installed  $dest"
}

uninstall_from() {
  local dest="$1/$SKILL_NAME"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    remove_destination "$dest" || die "Could not remove $dest"
    info "  removed    $dest"
  fi
}

# check_destinations AGENTS [separate]: every destination is checked before the
# first one is touched, so a refusal never leaves a half-done run.
check_destinations() {
  local name dest
  for name in $1; do
    dest="$(agent_skills_dir "$name")/$SKILL_NAME"
    require_own_destination "$dest"
    [ -z "${2:-}" ] || require_separate_source "$dest"
  done
}

run_install() {
  local agents="$1" name dir
  resolve_source
  check_destinations "$agents" separate
  check_command_sources "$agents"
  info "Installing ${SKILL_NAME} for:${agents}"
  for name in $agents; do
    dir=$(agent_skills_dir "$name")
    already_done "$dir" && continue
    install_into "$dir"
    install_command "$name"
    DONE_DIRS="$DONE_DIRS|$dir|"
  done
  info "Done. Restart your AI agent, then type /${SKILL_NAME} (in Codex: \$${SKILL_NAME}),"
  info "or ask it something like: \"My disk is almost full, help me free up space.\""
}

run_uninstall() {
  local agents="$1" name dir
  check_destinations "$agents"
  info "Removing ${SKILL_NAME} ..."
  for name in $agents; do
    dir=$(agent_skills_dir "$name")
    already_done "$dir" && continue
    uninstall_from "$dir"
    uninstall_command "$name"
    DONE_DIRS="$DONE_DIRS|$dir|"
  done
  info "Done."
}

main() {
  local agents
  parse_args "$@"
  require_home
  trap cleanup_tmp EXIT
  if [ "$MODE" = "uninstall" ]; then
    run_uninstall "${REQUESTED_AGENTS:- $KNOWN_AGENTS}"
    return 0
  fi
  warn_if_unsupported_os
  agents="${REQUESTED_AGENTS:-$(detected_agents)}"
  [ -n "$agents" ] ||
    die "No supported AI agent found on this machine. Pick one with --agent (names: $KNOWN_AGENTS)."
  run_install "$agents"
}

main "$@"
