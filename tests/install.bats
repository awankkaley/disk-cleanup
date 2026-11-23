#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SANDBOX="$(mktemp -d "${BATS_TMPDIR}/install-test.XXXXXX")"
  SANDBOX="$(cd "$SANDBOX" && pwd -P)"
  FAKE_HOME="$SANDBOX/home"
  CHECKOUT="$SANDBOX/checkout"
  STUB_BIN="$SANDBOX/bin"
  mkdir -p "$FAKE_HOME" "$CHECKOUT/scripts/lib" "$CHECKOUT/tests" "$CHECKOUT/.github" "$STUB_BIN"

  cp "$REPO_ROOT/install.sh" "$CHECKOUT/install.sh"
  printf -- '---\nname: disk-cleanup\ndescription: fixture\n---\n' >"$CHECKOUT/SKILL.md"
  printf 'MIT fixture\n' >"$CHECKOUT/LICENSE"
  printf '#!/bin/bash\nexit 0\n' >"$CHECKOUT/scripts/cleanup.sh"
  printf 'exit 0\n' >"$CHECKOUT/scripts/cleanup.ps1"
  printf 'helper\n' >"$CHECKOUT/scripts/lib/helper.sh"
  printf 'readme\n' >"$CHECKOUT/README.md"
  printf 'test\n' >"$CHECKOUT/tests/some.bats"
  cp -R "$REPO_ROOT/commands" "$CHECKOUT/commands"
  GEMINI_COMMAND="$FAKE_HOME/.gemini/commands/disk-cleanup.toml"
  OPENCODE_COMMAND="$FAKE_HOME/.config/opencode/commands/disk-cleanup.md"

  # Any network or cleanup-script execution would be a bug: make it fail loudly.
  printf '#!/bin/bash\necho "curl must not be called" >&2\nexit 97\n' >"$STUB_BIN/curl"
  chmod +x "$STUB_BIN/curl"
}

teardown() {
  rm -rf "$SANDBOX"
}

run_installer() {
  run env -i HOME="$FAKE_HOME" PATH="$STUB_BIN:/usr/bin:/bin" TMPDIR="$SANDBOX/tmp-unused" \
    /bin/bash "$CHECKOUT/install.sh" "$@"
}

snapshot_home() {
  (cd "$FAKE_HOME" && find . | LC_ALL=C sort)
}

@test "help prints usage and exits 0 without touching HOME" {
  run_installer --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--agent"* ]]
  [[ "$output" == *"--uninstall"* ]]
  [[ "$output" == *"--local"* ]]
  [ "$(snapshot_home)" = "." ]
}

@test "installs only SKILL.md, LICENSE and scripts for a detected agent" {
  mkdir -p "$FAKE_HOME/.claude"
  run_installer --local "$CHECKOUT"
  [ "$status" -eq 0 ]
  local dest="$FAKE_HOME/.claude/skills/disk-cleanup"
  [ -f "$dest/SKILL.md" ]
  [ -f "$dest/LICENSE" ]
  [ -f "$dest/scripts/cleanup.sh" ]
  [ -f "$dest/scripts/cleanup.ps1" ]
  [ -f "$dest/scripts/lib/helper.sh" ]
  [ "$(cd "$dest" && ls -A | LC_ALL=C sort | tr '\n' ' ')" = "LICENSE SKILL.md scripts " ]
}

@test "installs to detected agents only" {
  mkdir -p "$FAKE_HOME/.claude" "$FAKE_HOME/.gemini" "$FAKE_HOME/.config/opencode"
  run_installer --local "$CHECKOUT"
  [ "$status" -eq 0 ]
  [ -f "$FAKE_HOME/.claude/skills/disk-cleanup/SKILL.md" ]
  [ -f "$FAKE_HOME/.gemini/skills/disk-cleanup/SKILL.md" ]
  [ -f "$FAKE_HOME/.config/opencode/skills/disk-cleanup/SKILL.md" ]
  [ ! -e "$FAKE_HOME/.cursor" ]
  [ ! -e "$FAKE_HOME/.agents" ]
  [ ! -e "$FAKE_HOME/.copilot" ]
  [ ! -e "$FAKE_HOME/.codex" ]
}

@test "codex is detected by its config dir and installed into the shared agents dir" {
  mkdir -p "$FAKE_HOME/.codex"
  run_installer --local "$CHECKOUT"
  [ "$status" -eq 0 ]
  [ -f "$FAKE_HOME/.agents/skills/disk-cleanup/SKILL.md" ]
  [ ! -e "$FAKE_HOME/.codex/skills" ]
}

@test "agents sharing one skills dir are installed once" {
  mkdir -p "$FAKE_HOME/.codex" "$FAKE_HOME/.agents" "$FAKE_HOME/.config/goose"
  run_installer --local "$CHECKOUT"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'installed ')" -eq 1 ]
}

@test "fails with a clear message when no agent is detected" {
  run_installer --local "$CHECKOUT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"No supported AI agent found"* ]]
  [ "$(snapshot_home)" = "." ]
}

@test "--agent installs only for the named agent even when others are detected" {
  mkdir -p "$FAKE_HOME/.claude" "$FAKE_HOME/.gemini"
  run_installer --local "$CHECKOUT" --agent cursor
  [ "$status" -eq 0 ]
  [ -f "$FAKE_HOME/.cursor/skills/disk-cleanup/SKILL.md" ]
  [ ! -e "$FAKE_HOME/.claude/skills" ]
  [ ! -e "$FAKE_HOME/.gemini/skills" ]
}

@test "--agent accepts a comma list and repeats" {
  run_installer --local "$CHECKOUT" --agent claude,cursor --agent gemini
  [ "$status" -eq 0 ]
  [ -f "$FAKE_HOME/.claude/skills/disk-cleanup/SKILL.md" ]
  [ -f "$FAKE_HOME/.cursor/skills/disk-cleanup/SKILL.md" ]
  [ -f "$FAKE_HOME/.gemini/skills/disk-cleanup/SKILL.md" ]
  [ ! -e "$FAKE_HOME/.agents" ]
}

@test "unknown agent name is a usage error and writes nothing" {
  run_installer --local "$CHECKOUT" --agent notepad
  [ "$status" -eq 2 ]
  [[ "$output" == *"Unknown agent"* ]]
  [ "$(snapshot_home)" = "." ]
}

@test "unknown option is a usage error" {
  run_installer --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"Unknown option"* ]]
}

@test "re-install is idempotent and drops stale files from an older version" {
  mkdir -p "$FAKE_HOME/.claude"
  run_installer --local "$CHECKOUT"
  [ "$status" -eq 0 ]
  local before
  before="$(snapshot_home)"
  printf 'stale\n' >"$FAKE_HOME/.claude/skills/disk-cleanup/scripts/old-version.sh"
  run_installer --local "$CHECKOUT"
  [ "$status" -eq 0 ]
  [ "$(snapshot_home)" = "$before" ]
}

@test "install leaves sibling skills and other agent files alone" {
  mkdir -p "$FAKE_HOME/.claude/skills/other-skill" "$FAKE_HOME/Documents"
  printf 'keep\n' >"$FAKE_HOME/.claude/skills/other-skill/SKILL.md"
  printf 'keep\n' >"$FAKE_HOME/.claude/settings.json"
  printf 'keep\n' >"$FAKE_HOME/Documents/note.txt"
  local before
  before="$(snapshot_home)"
  run_installer --local "$CHECKOUT"
  [ "$status" -eq 0 ]
  local after_without_skill
  after_without_skill="$(snapshot_home | grep -v '^\./\.claude/skills/disk-cleanup')"
  [ "$after_without_skill" = "$before" ]
  [ "$(cat "$FAKE_HOME/.claude/skills/other-skill/SKILL.md")" = "keep" ]
}

@test "install does not modify the local checkout" {
  mkdir -p "$FAKE_HOME/.claude"
  local before
  before="$(cd "$CHECKOUT" && find . | LC_ALL=C sort)"
  run_installer --local "$CHECKOUT"
  [ "$status" -eq 0 ]
  [ "$(cd "$CHECKOUT" && find . | LC_ALL=C sort)" = "$before" ]
}

@test "--uninstall removes only the disk-cleanup dir" {
  mkdir -p "$FAKE_HOME/.claude/skills/other-skill" "$FAKE_HOME/.cursor"
  printf 'keep\n' >"$FAKE_HOME/.claude/skills/other-skill/SKILL.md"
  local before
  before="$(snapshot_home)"
  run_installer --local "$CHECKOUT"
  [ "$status" -eq 0 ]
  [ -d "$FAKE_HOME/.claude/skills/disk-cleanup" ]
  [ -d "$FAKE_HOME/.cursor/skills/disk-cleanup" ]

  run_installer --uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE_HOME/.claude/skills/disk-cleanup" ]
  [ ! -e "$FAKE_HOME/.cursor/skills/disk-cleanup" ]
  [ -f "$FAKE_HOME/.claude/skills/other-skill/SKILL.md" ]
  [ "$(snapshot_home | grep -v '^\./\.cursor/skills$')" = "$before" ]
}

@test "--uninstall with --agent removes only that agent's copy" {
  run_installer --local "$CHECKOUT" --agent claude,cursor
  [ "$status" -eq 0 ]
  run_installer --uninstall --agent cursor
  [ "$status" -eq 0 ]
  [ -d "$FAKE_HOME/.claude/skills/disk-cleanup" ]
  [ ! -e "$FAKE_HOME/.cursor/skills/disk-cleanup" ]
}

@test "--uninstall when nothing is installed succeeds and writes nothing" {
  mkdir -p "$FAKE_HOME/.claude"
  local before
  before="$(snapshot_home)"
  run_installer --uninstall
  [ "$status" -eq 0 ]
  [ "$(snapshot_home)" = "$before" ]
}

@test "--uninstall removes a symlinked skill without touching its target" {
  mkdir -p "$FAKE_HOME/.claude/skills" "$SANDBOX/elsewhere"
  printf 'keep\n' >"$SANDBOX/elsewhere/SKILL.md"
  ln -s "$SANDBOX/elsewhere" "$FAKE_HOME/.claude/skills/disk-cleanup"
  run_installer --uninstall
  [ "$status" -eq 0 ]
  [ ! -L "$FAKE_HOME/.claude/skills/disk-cleanup" ]
  [ -f "$SANDBOX/elsewhere/SKILL.md" ]
}

@test "--local pointing at the installed copy aborts without deleting it" {
  run_installer --local "$CHECKOUT" --agent claude
  [ "$status" -eq 0 ]
  local dest="$FAKE_HOME/.claude/skills/disk-cleanup" before
  before="$(snapshot_home)"
  run_installer --local "$dest" --agent claude
  [ "$status" -ne 0 ]
  [[ "$output" == *"overlap"* ]]
  [ "$(snapshot_home)" = "$before" ]
  [ -f "$dest/scripts/cleanup.sh" ]
}

@test "--local reaching the destination through a symlink aborts as well" {
  run_installer --local "$CHECKOUT" --agent claude
  ln -s "$FAKE_HOME/.claude/skills/disk-cleanup" "$SANDBOX/alias"
  local before
  before="$(snapshot_home)"
  run_installer --local "$SANDBOX/alias" --agent claude
  [ "$status" -ne 0 ]
  [[ "$output" == *"overlap"* ]]
  [ "$(snapshot_home)" = "$before" ]
}

@test "a destination that is a symlink to the source aborts and keeps the source" {
  mkdir -p "$FAKE_HOME/.claude/skills"
  ln -s "$CHECKOUT" "$FAKE_HOME/.claude/skills/disk-cleanup"
  run_installer --local "$CHECKOUT" --agent claude
  [ "$status" -ne 0 ]
  [[ "$output" == *"overlap"* ]]
  [ -f "$CHECKOUT/SKILL.md" ]
  [ -L "$FAKE_HOME/.claude/skills/disk-cleanup" ]
}

@test "a source that contains the destination aborts" {
  local skills="$FAKE_HOME/.claude/skills"
  run_installer --local "$CHECKOUT" --agent claude
  cp "$CHECKOUT/SKILL.md" "$CHECKOUT/LICENSE" "$skills/"
  cp -R "$CHECKOUT/scripts" "$skills/scripts"
  local before
  before="$(snapshot_home)"
  run_installer --local "$skills" --agent claude
  [ "$status" -ne 0 ]
  [[ "$output" == *"overlap"* ]]
  [ "$(snapshot_home)" = "$before" ]
}

@test "an overlap with any destination aborts before the first one is replaced" {
  run_installer --local "$CHECKOUT" --agent claude,cursor
  printf 'marker\n' >"$FAKE_HOME/.claude/skills/disk-cleanup/scripts/marker"
  run_installer --local "$FAKE_HOME/.cursor/skills/disk-cleanup" --agent claude,cursor
  [ "$status" -ne 0 ]
  [ -f "$FAKE_HOME/.claude/skills/disk-cleanup/scripts/marker" ]
}

@test "install refuses to replace a foreign disk-cleanup folder" {
  local dest="$FAKE_HOME/.claude/skills/disk-cleanup"
  mkdir -p "$dest"
  printf 'precious\n' >"$dest/notes.txt"
  run_installer --local "$CHECKOUT" --agent claude
  [ "$status" -ne 0 ]
  [[ "$output" == *"not this skill"* ]]
  [ "$(cat "$dest/notes.txt")" = "precious" ]
  printf -- '---\nname: other-skill\n---\nname: disk-cleanup\n' >"$dest/SKILL.md"
  run_installer --local "$CHECKOUT" --agent claude
  [ "$status" -ne 0 ]
  [ "$(cat "$dest/notes.txt")" = "precious" ]
}

@test "install refuses a foreign folder before touching any other agent" {
  mkdir -p "$FAKE_HOME/.cursor/skills/disk-cleanup"
  printf 'precious\n' >"$FAKE_HOME/.cursor/skills/disk-cleanup/notes.txt"
  run_installer --local "$CHECKOUT" --agent claude,cursor
  [ "$status" -ne 0 ]
  [ ! -e "$FAKE_HOME/.claude/skills/disk-cleanup" ]
}

@test "--uninstall refuses to remove a foreign disk-cleanup folder" {
  local dest="$FAKE_HOME/.claude/skills/disk-cleanup"
  mkdir -p "$dest"
  printf 'precious\n' >"$dest/notes.txt"
  run_installer --uninstall --agent claude
  [ "$status" -ne 0 ]
  [[ "$output" == *"not this skill"* ]]
  [ "$(cat "$dest/notes.txt")" = "precious" ]
}

@test "--uninstall refuses a foreign folder before removing any other copy" {
  run_installer --local "$CHECKOUT" --agent claude
  mkdir -p "$FAKE_HOME/.cursor/skills/disk-cleanup"
  printf 'precious\n' >"$FAKE_HOME/.cursor/skills/disk-cleanup/notes.txt"
  run_installer --uninstall --agent claude,cursor
  [ "$status" -ne 0 ]
  [ -f "$FAKE_HOME/.claude/skills/disk-cleanup/SKILL.md" ]
}

@test "--local pointing at a folder without SKILL.md fails and installs nothing" {
  mkdir -p "$FAKE_HOME/.claude" "$SANDBOX/empty"
  run_installer --local "$SANDBOX/empty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SKILL.md"* ]]
  [ ! -e "$FAKE_HOME/.claude/skills" ]
}

@test "failed download exits non-zero, installs nothing and removes its temp dir" {
  mkdir -p "$FAKE_HOME/.claude" "$SANDBOX/tmp-unused"
  run_installer
  [ "$status" -ne 0 ]
  [[ "$output" == *"Download failed"* ]]
  [ ! -e "$FAKE_HOME/.claude/skills" ]
  [ -z "$(ls -A "$SANDBOX/tmp-unused")" ]
}

@test "warns on an unsupported OS but still installs" {
  mkdir -p "$FAKE_HOME/.claude"
  printf '#!/bin/bash\necho Linux\n' >"$STUB_BIN/uname"
  chmod +x "$STUB_BIN/uname"
  run_installer --local "$CHECKOUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"only cleans macOS and Windows"* ]]
  [ -f "$FAKE_HOME/.claude/skills/disk-cleanup/SKILL.md" ]
}

@test "never runs the cleanup script" {
  mkdir -p "$FAKE_HOME/.claude"
  printf '#!/bin/bash\ntouch "%s/cleanup-was-run"\n' "$SANDBOX" >"$CHECKOUT/scripts/cleanup.sh"
  chmod +x "$CHECKOUT/scripts/cleanup.sh"
  run_installer --local "$CHECKOUT"
  [ "$status" -eq 0 ]
  [ ! -e "$SANDBOX/cleanup-was-run" ]
}

@test "command files are installed for gemini and opencode and for no other agent" {
  run_installer --local "$CHECKOUT" --agent claude,codex,cursor,gemini,copilot,opencode,amp,goose,agents
  [ "$status" -eq 0 ]
  cmp -s "$CHECKOUT/commands/gemini/disk-cleanup.toml" "$GEMINI_COMMAND"
  cmp -s "$CHECKOUT/commands/opencode/disk-cleanup.md" "$OPENCODE_COMMAND"
  local commands
  commands="$(cd "$FAKE_HOME" && find . -path '*/skills' -prune -o \( -name 'disk-cleanup.*' -o -name commands -o -name prompts \) -print | LC_ALL=C sort | tr '\n' ' ')"
  [ "$commands" = "./.config/opencode/commands ./.config/opencode/commands/disk-cleanup.md ./.gemini/commands ./.gemini/commands/disk-cleanup.toml " ]
  [ "$(cd "$FAKE_HOME/.gemini/skills/disk-cleanup" && ls -A | LC_ALL=C sort | tr '\n' ' ')" = "LICENSE SKILL.md scripts " ]
}

@test "agents whose skills are already invocable get no command file" {
  mkdir -p "$FAKE_HOME/.claude" "$FAKE_HOME/.cursor" "$FAKE_HOME/.copilot" "$FAKE_HOME/.codex"
  run_installer --local "$CHECKOUT"
  [ "$status" -eq 0 ]
  [ -z "$(cd "$FAKE_HOME" && find . -name commands -o -name prompts -o -name 'disk-cleanup.*')" ]
}

@test "re-install refreshes our own command file" {
  run_installer --local "$CHECKOUT" --agent gemini
  [ "$status" -eq 0 ]
  printf '# disk-cleanup-skill:managed-command\nprompt = "stale"\n' >"$GEMINI_COMMAND"
  run_installer --local "$CHECKOUT" --agent gemini
  [ "$status" -eq 0 ]
  cmp -s "$CHECKOUT/commands/gemini/disk-cleanup.toml" "$GEMINI_COMMAND"
}

@test "--uninstall removes our command files and keeps the user's other commands" {
  mkdir -p "$FAKE_HOME/.gemini/commands" "$FAKE_HOME/.config/opencode/commands"
  printf 'prompt = "mine"\n' >"$FAKE_HOME/.gemini/commands/other.toml"
  printf 'mine\n' >"$FAKE_HOME/.config/opencode/commands/other.md"
  local before
  before="$(snapshot_home)"
  run_installer --local "$CHECKOUT"
  [ "$status" -eq 0 ]
  [ -f "$GEMINI_COMMAND" ]
  [ -f "$OPENCODE_COMMAND" ]

  run_installer --uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$GEMINI_COMMAND" ]
  [ ! -e "$OPENCODE_COMMAND" ]
  [ "$(cat "$FAKE_HOME/.gemini/commands/other.toml")" = 'prompt = "mine"' ]
  [ "$(snapshot_home | grep -v '/skills$')" = "$before" ]
}

@test "--uninstall with --agent removes only that agent's command file" {
  run_installer --local "$CHECKOUT" --agent gemini,opencode
  [ "$status" -eq 0 ]
  run_installer --uninstall --agent gemini
  [ "$status" -eq 0 ]
  [ ! -e "$GEMINI_COMMAND" ]
  [ -f "$OPENCODE_COMMAND" ]
}

@test "a foreign command file of the same name is never replaced or removed" {
  mkdir -p "$FAKE_HOME/.gemini/commands" "$FAKE_HOME/.config/opencode/commands"
  printf 'prompt = "my own disk-cleanup command"\n' >"$GEMINI_COMMAND"
  printf 'my own disk-cleanup command\n' >"$OPENCODE_COMMAND"

  run_installer --local "$CHECKOUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped    $GEMINI_COMMAND"* ]]
  [[ "$output" == *"skipped    $OPENCODE_COMMAND"* ]]
  [ "$(cat "$GEMINI_COMMAND")" = 'prompt = "my own disk-cleanup command"' ]
  [ "$(cat "$OPENCODE_COMMAND")" = "my own disk-cleanup command" ]
  [ -f "$FAKE_HOME/.gemini/skills/disk-cleanup/SKILL.md" ]

  run_installer --uninstall
  [ "$status" -eq 0 ]
  [[ "$output" == *"kept       $GEMINI_COMMAND"* ]]
  [ "$(cat "$GEMINI_COMMAND")" = 'prompt = "my own disk-cleanup command"' ]
  [ "$(cat "$OPENCODE_COMMAND")" = "my own disk-cleanup command" ]
  [ ! -e "$FAKE_HOME/.gemini/skills/disk-cleanup" ]
}

@test "a symlinked command file is left alone, and so is its target" {
  mkdir -p "$FAKE_HOME/.gemini/commands" "$SANDBOX/elsewhere"
  printf '# disk-cleanup-skill:managed-command\nprompt = "linked"\n' >"$SANDBOX/elsewhere/linked.toml"
  ln -s "$SANDBOX/elsewhere/linked.toml" "$GEMINI_COMMAND"
  run_installer --local "$CHECKOUT" --agent gemini
  [ "$status" -eq 0 ]
  run_installer --uninstall --agent gemini
  [ "$status" -eq 0 ]
  [ -L "$GEMINI_COMMAND" ]
  [ "$(sed -n 2p "$SANDBOX/elsewhere/linked.toml")" = 'prompt = "linked"' ]
}

@test "a source without the command file fails before anything is installed" {
  mv "$CHECKOUT/commands" "$SANDBOX/commands-moved-away"
  run_installer --local "$CHECKOUT" --agent claude,gemini
  [ "$status" -ne 0 ]
  [[ "$output" == *"commands/gemini/disk-cleanup.toml"* ]]
  [ "$(snapshot_home)" = "." ]
  run_installer --local "$CHECKOUT" --agent claude
  [ "$status" -eq 0 ]
  [ -f "$FAKE_HOME/.claude/skills/disk-cleanup/SKILL.md" ]
}

@test "shipped command files carry the marker, pass the arguments and hold no script paths" {
  local file
  for file in "$REPO_ROOT/commands/gemini/disk-cleanup.toml" "$REPO_ROOT/commands/opencode/disk-cleanup.md"; do
    grep -qF 'disk-cleanup-skill:managed-command' "$file"
    run grep -qE 'cleanup\.(sh|ps1)|scripts/|--token|--categories' "$file"
    [ "$status" -eq 1 ]
  done
  grep -qF '{{args}}' "$REPO_ROOT/commands/gemini/disk-cleanup.toml"
  grep -qF '$ARGUMENTS' "$REPO_ROOT/commands/opencode/disk-cleanup.md"
  [ "$(find "$REPO_ROOT/commands" -type f | wc -l | tr -d ' ')" = "2" ]
}

@test "SKILL.md takes optional arguments and never lets them skip the confirmation" {
  local skill="$REPO_ROOT/SKILL.md"
  [ "$(grep -cF '$ARGUMENTS' "$skill")" -eq 1 ]
  grep -q '^  version: "1.1.0"$' "$skill"
  grep -qi 'arguments never skip' "$skill"
  run grep -qE '\$[0-9]' "$skill"
  [ "$status" -eq 1 ]
}

@test "pinned version and download URL point at the v1.1.0 tag" {
  grep -q '^VERSION="v1.1.0"$' "$REPO_ROOT/install.sh"
  grep -q "^    \$Version = 'v1.1.0'\$" "$REPO_ROOT/install.ps1"
  run grep -q 'v1\.0\.0' "$REPO_ROOT/README.md" "$REPO_ROOT/README.id.md" "$REPO_ROOT/install.sh" "$REPO_ROOT/install.ps1"
  [ "$status" -eq 1 ]
  grep -q 'github.com/${REPO}/archive/refs/tags/${VERSION}.tar.gz' "$REPO_ROOT/install.sh"
}
