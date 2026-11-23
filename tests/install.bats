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
  cp -R "$REPO_ROOT/.claude-plugin" "$REPO_ROOT/skills" "$CHECKOUT/"
  JSON_TOOL="$REPO_ROOT/tests/helpers/json.pl"
  MODES="scan scan-only review deep help"
  GEMINI_COMMAND="$FAKE_HOME/.gemini/commands/disk-cleanup.toml"
  OPENCODE_COMMAND="$FAKE_HOME/.config/opencode/commands/disk-cleanup.md"
  GEMINI_NAMESPACE="$FAKE_HOME/.gemini/commands/disk-cleanup"
  OPENCODE_NAMESPACE="$FAKE_HOME/.config/opencode/commands/disk-cleanup"

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
  [ -d "$CHECKOUT/.claude-plugin" ]
  [ -d "$CHECKOUT/skills" ]
  [ -z "$(find "$FAKE_HOME" -name .claude-plugin -o -name plugin.json -o -name marketplace.json)" ]
  [ "$(find "$FAKE_HOME" -name SKILL.md | wc -l | tr -d ' ')" = "1" ]
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
  commands="$(cd "$FAKE_HOME" && find . -path '*/skills' -prune -o \( -name 'disk-cleanup*' -o -name commands -o -name prompts \) -print | LC_ALL=C sort | tr '\n' ' ')"
  [ "$commands" = "./.config/opencode/commands ./.config/opencode/commands/disk-cleanup ./.config/opencode/commands/disk-cleanup.md ./.gemini/commands ./.gemini/commands/disk-cleanup ./.gemini/commands/disk-cleanup.toml " ]
  [ "$(cd "$FAKE_HOME/.gemini/skills/disk-cleanup" && ls -A | LC_ALL=C sort | tr '\n' ' ')" = "LICENSE SKILL.md scripts " ]
}

@test "agents whose skills are already invocable get no command file" {
  mkdir -p "$FAKE_HOME/.claude" "$FAKE_HOME/.cursor" "$FAKE_HOME/.copilot" "$FAKE_HOME/.codex"
  run_installer --local "$CHECKOUT"
  [ "$status" -eq 0 ]
  [ -z "$(cd "$FAKE_HOME" && find . -name commands -o -name prompts -o -name 'disk-cleanup.*')" ]
  [ "$(cd "$FAKE_HOME" && find . -name disk-cleanup | grep -vc '/skills/disk-cleanup$')" = "0" ]
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
  [ "$(find "$REPO_ROOT/commands" -type f | wc -l | tr -d ' ')" = "12" ]
  while IFS= read -r file; do
    grep -qF 'disk-cleanup-skill:managed-command' "$file"
    grep -qF 'approves nothing' "$file"
    grep -qF 'hard rules included' "$file"
    run grep -qE 'cleanup\.(sh|ps1)|scripts/|--token|--categories' "$file"
    [ "$status" -eq 1 ]
    case "$file" in
      *.toml) grep -qF '{{args}}' "$file" ;;
      *.md) grep -qF '$ARGUMENTS' "$file" ;;
      *) false ;;
    esac
  done < <(find "$REPO_ROOT/commands" -type f)
}

@test "each namespaced command file fixes exactly its own mode" {
  local mode other file
  for mode in $MODES; do
    for file in "$REPO_ROOT/commands/gemini/disk-cleanup/$mode.toml" "$REPO_ROOT/commands/opencode/disk-cleanup/$mode.md"; do
      grep -qF "in the mode \`$mode\`:" "$file"
      for other in $MODES; do
        [ "$other" != "$mode" ] || continue
        run grep -qF "\`$other\`" "$file"
        [ "$status" -eq 1 ]
      done
    done
  done
  [ "$(find "$REPO_ROOT/commands" -mindepth 3 -type f | wc -l | tr -d ' ')" = "10" ]
}

@test "namespaced command files are installed into a disk-cleanup subfolder" {
  run_installer --local "$CHECKOUT" --agent gemini,opencode
  [ "$status" -eq 0 ]
  local mode
  for mode in $MODES; do
    cmp -s "$CHECKOUT/commands/gemini/disk-cleanup/$mode.toml" "$GEMINI_NAMESPACE/$mode.toml"
    cmp -s "$CHECKOUT/commands/opencode/disk-cleanup/$mode.md" "$OPENCODE_NAMESPACE/$mode.md"
  done
  [ "$(ls -A "$GEMINI_NAMESPACE" | LC_ALL=C sort | tr '\n' ' ')" = "deep.toml help.toml review.toml scan-only.toml scan.toml " ]
  [ "$(ls -A "$OPENCODE_NAMESPACE" | LC_ALL=C sort | tr '\n' ' ')" = "deep.md help.md review.md scan-only.md scan.md " ]
}

@test "re-install refreshes our namespaced command files and --uninstall removes the empty subfolder" {
  run_installer --local "$CHECKOUT" --agent gemini
  [ "$status" -eq 0 ]
  printf '# disk-cleanup-skill:managed-command\nprompt = "stale"\n' >"$GEMINI_NAMESPACE/deep.toml"
  run_installer --local "$CHECKOUT" --agent gemini
  [ "$status" -eq 0 ]
  cmp -s "$CHECKOUT/commands/gemini/disk-cleanup/deep.toml" "$GEMINI_NAMESPACE/deep.toml"

  run_installer --uninstall --agent gemini
  [ "$status" -eq 0 ]
  [ ! -e "$GEMINI_NAMESPACE" ]
  [ -d "$FAKE_HOME/.gemini/commands" ]
}

@test "foreign files in the namespace subfolder are never replaced or removed" {
  mkdir -p "$GEMINI_NAMESPACE" "$OPENCODE_NAMESPACE"
  printf 'prompt = "my own deep"\n' >"$GEMINI_NAMESPACE/deep.toml"
  printf 'prompt = "my extra"\n' >"$GEMINI_NAMESPACE/mine.toml"
  printf 'my own help\n' >"$OPENCODE_NAMESPACE/help.md"

  run_installer --local "$CHECKOUT" --agent gemini,opencode
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped    $GEMINI_NAMESPACE/deep.toml"* ]]
  [[ "$output" == *"skipped    $OPENCODE_NAMESPACE/help.md"* ]]
  [ "$(cat "$GEMINI_NAMESPACE/deep.toml")" = 'prompt = "my own deep"' ]
  [ "$(cat "$OPENCODE_NAMESPACE/help.md")" = "my own help" ]
  [ -f "$GEMINI_NAMESPACE/scan.toml" ]
  [ -f "$OPENCODE_NAMESPACE/scan-only.md" ]

  run_installer --uninstall --agent gemini,opencode
  [ "$status" -eq 0 ]
  [[ "$output" == *"kept       $GEMINI_NAMESPACE/deep.toml"* ]]
  [ "$(ls -A "$GEMINI_NAMESPACE" | LC_ALL=C sort | tr '\n' ' ')" = "deep.toml mine.toml " ]
  [ "$(cat "$GEMINI_NAMESPACE/deep.toml")" = 'prompt = "my own deep"' ]
  [ "$(cat "$GEMINI_NAMESPACE/mine.toml")" = 'prompt = "my extra"' ]
  [ "$(ls -A "$OPENCODE_NAMESPACE")" = "help.md" ]
  [ "$(cat "$OPENCODE_NAMESPACE/help.md")" = "my own help" ]
}

@test "a symlinked namespace subfolder is left alone, and so is its target" {
  mkdir -p "$FAKE_HOME/.gemini/commands" "$SANDBOX/elsewhere"
  printf '# disk-cleanup-skill:managed-command\nprompt = "linked"\n' >"$SANDBOX/elsewhere/deep.toml"
  ln -s "$SANDBOX/elsewhere" "$GEMINI_NAMESPACE"

  run_installer --local "$CHECKOUT" --agent gemini
  [ "$status" -eq 0 ]
  [ -f "$GEMINI_COMMAND" ]
  [ "$(ls -A "$SANDBOX/elsewhere")" = "deep.toml" ]
  [ "$(sed -n 2p "$SANDBOX/elsewhere/deep.toml")" = 'prompt = "linked"' ]

  run_installer --uninstall --agent gemini
  [ "$status" -eq 0 ]
  [ ! -e "$GEMINI_COMMAND" ]
  [ -L "$GEMINI_NAMESPACE" ]
  [ "$(sed -n 2p "$SANDBOX/elsewhere/deep.toml")" = 'prompt = "linked"' ]
}

@test "a namespace path that is a plain file is left alone and does not stop the install" {
  mkdir -p "$FAKE_HOME/.gemini/commands"
  printf 'mine\n' >"$GEMINI_NAMESPACE"
  run_installer --local "$CHECKOUT" --agent gemini
  [ "$status" -eq 0 ]
  [ "$(cat "$GEMINI_NAMESPACE")" = "mine" ]
  [ -f "$GEMINI_COMMAND" ]
  [ -f "$FAKE_HOME/.gemini/skills/disk-cleanup/SKILL.md" ]
  run_installer --uninstall --agent gemini
  [ "$status" -eq 0 ]
  [ "$(cat "$GEMINI_NAMESPACE")" = "mine" ]
}

@test "a source without a namespaced command file fails before anything is installed" {
  rm "$CHECKOUT/commands/gemini/disk-cleanup/scan-only.toml"
  run_installer --local "$CHECKOUT" --agent claude,gemini
  [ "$status" -ne 0 ]
  [[ "$output" == *"commands/gemini/disk-cleanup/scan-only.toml"* ]]
  [ "$(snapshot_home)" = "." ]
  printf 'prompt = "no marker"\n' >"$CHECKOUT/commands/gemini/disk-cleanup/scan-only.toml"
  run_installer --local "$CHECKOUT" --agent gemini
  [ "$status" -ne 0 ]
  [ "$(snapshot_home)" = "." ]
}

@test "SKILL.md takes optional arguments and never lets them skip the confirmation" {
  local skill="$REPO_ROOT/SKILL.md"
  [ "$(grep -cF '$ARGUMENTS' "$skill")" -eq 1 ]
  grep -q '^  version: "1.2.0"$' "$skill"
  grep -qi 'arguments never skip' "$skill"
  run grep -qE '\$[0-9]' "$skill"
  [ "$status" -eq 1 ]
}

@test "SKILL.md documents scan as the default and scan-only as a mode that never cleans" {
  local skill="$REPO_ROOT/SKILL.md" phrase
  grep -qF '| none, or `scan` |' "$skill"
  for phrase in '`scan-only`' '"report"' '"just check"' '"cek saja"' '"lihat saja"'; do
    grep -F '| `scan-only` (' "$skill" | grep -qF "$phrase"
  done
  grep -q '^### Scan only' "$skill"
  grep -qi 'do not run `clean` in this' "$skill"
  grep -q '^12\. Arguments never skip the confirmation step\.' "$skill"
}

@test "SKILL.md documents review as a mode whose files the AI never reads" {
  local skill="$REPO_ROOT/SKILL.md" phrase
  grep -qF '| `review` (' "$skill"
  grep -q '^### Review' "$skill"
  grep -qF 'review-apply --token' "$skill"
  grep -q '^13\. Never open, read, print, search or summarise the review page' "$skill"
  grep -q '^14\. Never ask the user to type or paste file or folder names' "$skill"
  grep -q '^16\. Never run `review` and `review-apply` in the same turn\.' "$skill"
  for phrase in 'report_location_hint' 'SELECTION_NOT_FOUND' 'SELECTION_INVALID' 'Save selection' \
    'space_freed_when_trash_emptied' 'ONLY they can see that page'; do
    grep -qF "$phrase" "$skill"
  done
}

@test "SKILL.md documents the target form and the plain-language presentation rules" {
  local skill="$REPO_ROOT/SKILL.md" phrase
  grep -q '^### Target' "$skill"
  grep -q '^### How to talk to the user' "$skill"
  for phrase in 'scan --target-gb N' '`10gb`' 'suggestion.category_ids' 'reaches_target' 'rebuild_cost' \
    'Never show `not_found` rows' '"Developer tools" heading' 'The suggestion approves nothing'; do
    grep -qF "$phrase" "$skill"
  done
}

json_get() {
  /usr/bin/perl "$JSON_TOOL" get "$2" <"$1"
}

# Value of one frontmatter key of a SKILL.md.
frontmatter_value() {
  awk -v key="$2" '
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    index($0, key ":") == 1 { sub(/^[^:]*:[ \t]*/, ""); gsub(/^"|"$/, ""); print; exit }' "$1"
}

@test "plugin manifests parse and agree with SKILL.md on name and version" {
  local plugin="$REPO_ROOT/.claude-plugin/plugin.json" market="$REPO_ROOT/.claude-plugin/marketplace.json"
  local version
  version="$(sed -n 's/^  version: "\(.*\)"$/\1/p' "$REPO_ROOT/SKILL.md")"
  [ -n "$version" ]
  [ "$(json_get "$plugin" name)" = "$(frontmatter_value "$REPO_ROOT/SKILL.md" name)" ]
  [ "$(json_get "$plugin" name)" = "disk-cleanup" ]
  [ "$(json_get "$plugin" version)" = "$version" ]
  [ "v$(json_get "$plugin" version)" = "$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$REPO_ROOT/install.sh")" ]
  [ "$(json_get "$plugin" author.name)" = "awankkaley" ]
  [ "$(json_get "$plugin" license)" = "MIT" ]
  [ "$(json_get "$plugin" repository)" = "https://github.com/awankkaley/disk-cleanup" ]
  # commands/ holds Gemini CLI and OpenCode files; Claude Code must not load them as plugin commands.
  [ "$(json_get "$plugin" commands)" = "[]" ]
  [ -n "$(json_get "$market" name)" ]
  [ "$(json_get "$market" owner.name)" = "awankkaley" ]
  [ "$(json_get "$market" plugins.0.name)" = "disk-cleanup" ]
  [ "$(json_get "$market" plugins.0.source)" = "./" ]
  [ "$(json_get "$market" plugins.1.name)" = "null" ]
  [ "$(ls -A "$REPO_ROOT/.claude-plugin" | LC_ALL=C sort | tr '\n' ' ')" = "marketplace.json plugin.json " ]
}

@test "plugin skills are thin: one per mode, named after their folder, with no rules of their own" {
  local mode file
  [ "$(ls -A "$REPO_ROOT/skills" | LC_ALL=C sort | tr '\n' ' ')" = "deep help review scan scan-only " ]
  [ "$(find "$REPO_ROOT/skills" -type f | wc -l | tr -d ' ')" = "5" ]
  for mode in $MODES; do
    file="$REPO_ROOT/skills/$mode/SKILL.md"
    [ "$(frontmatter_value "$file" name)" = "$mode" ]
    [ -n "$(frontmatter_value "$file" description)" ]
    grep -qF "Mode for this invocation: \`$mode\`" "$file"
    grep -qF '${CLAUDE_PLUGIN_ROOT}/SKILL.md' "$file"
    grep -qF '${CLAUDE_PLUGIN_ROOT}/scripts/' "$file"
    grep -qF 'hard rules' "$file"
    grep -qF 'approves nothing' "$file"
    [ "$(grep -cF '$ARGUMENTS' "$file")" -eq 1 ]
    run grep -qiE 'clean --token|--token|--categories|--deep|--empty-trash|cleanup\.(sh|ps1)|sudo|^#|^\|' "$file"
    [ "$status" -eq 1 ]
    [ "$(wc -l <"$file" | tr -d ' ')" -le 25 ]
  done
}

@test "only the default plugin skill can be started by the model" {
  local mode
  run grep -q '^disable-model-invocation:' "$REPO_ROOT/skills/scan/SKILL.md"
  [ "$status" -eq 1 ]
  for mode in scan-only review deep help; do
    [ "$(frontmatter_value "$REPO_ROOT/skills/$mode/SKILL.md" disable-model-invocation)" = "true" ]
  done
}

@test "pinned version and download URL point at the v1.2.0 tag" {
  grep -q '^VERSION="v1.2.0"$' "$REPO_ROOT/install.sh"
  grep -q "^    \$Version = 'v1.2.0'\$" "$REPO_ROOT/install.ps1"
  run grep -qE 'v1\.[01]\.0' "$REPO_ROOT/README.md" "$REPO_ROOT/README.id.md" "$REPO_ROOT/install.sh" "$REPO_ROOT/install.ps1"
  [ "$status" -eq 1 ]
  grep -q 'github.com/${REPO}/archive/refs/tags/${VERSION}.tar.gz' "$REPO_ROOT/install.sh"
}
