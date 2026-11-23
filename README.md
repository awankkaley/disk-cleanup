# disk-cleanup

**English** | [Bahasa Indonesia](README.id.md)

An Agent Skill that lets your AI assistant (Claude Code, Codex CLI, Cursor, Gemini CLI and others) free
up disk space on macOS and Windows without ever seeing your files.

You type `/disk-cleanup` or just say "my disk is full". The assistant runs one script, shows you a table of what can be cleaned and
how much space each item would free, asks which ones you want, and cleans only those.

## What it does

- Finds junk that is safe to delete: app caches, temporary files, old logs, browser caches, and caches
  left behind by developer tools (npm, pip, Homebrew, Xcode, Docker and more).
- Shows the size of each category before anything is deleted. Nothing is removed until you choose.
- Optionally finds `node_modules` folders in projects you have not touched for months.
- Works without administrator rights and without installing anything else.

It does not look for large files, duplicates, or old downloads. Doing that would mean reading your file
names, and this skill is built to never do that.

## Privacy guarantees

There are two kinds of promises here, and they are not equally strong. Please read both.

### Enforced by the script

These hold no matter what the AI does, because the script is written that way and the tests check it.

- **The AI only receives totals.** The script prints one JSON document with category names, sizes,
  counts and statuses. It never prints file names, folder names, paths, your username, your computer
  name or project names. Error messages are fixed texts with nothing inserted into them.
- **Fixed list of locations.** The script can only clean the categories listed below. There is no
  "clean everything" mode and no way to pass it a folder to delete.
- **Guarded deletion.** Every deletion goes through one routine that refuses anything outside your
  home folder, anything too close to the top of it, any folder that contains a protected folder, and
  any symbolic link. Links are never followed.
- **Developer tools are asked first.** Before a tool's own clean command (npm, Yarn, pnpm, pip, Go,
  Homebrew) may run, the script asks the tool where its cache is. If that is not the tool's standard
  location, for example because a setting points it at Documents, the category is reported as
  unavailable and nothing is run or deleted.
- **The home folder cannot be swapped.** On macOS the script looks up your account's real home folder
  itself and refuses to run when `HOME` points at a folder inside it.
- **Scan first, then clean.** `clean` only works with a token from a scan made in the last 15 minutes,
  only for categories that scan reported, and the token works once. The trash is emptied only with an
  extra explicit flag.
- **No sudo, no administrator rights.** The script never elevates, never closes your apps, and never
  changes permissions. If an app is open, its cache is skipped.
- **No network.** The script sends nothing anywhere. (Some developer tools' own clean commands are
  called, such as `npm cache clean`; they work locally.)

### Instructions to the AI, not technically enforceable

The skill tells the AI to follow these rules. A well-behaved assistant will, but the script cannot
stop an assistant that has general access to your terminal from doing something else. Your agent's own
permission prompts are the real safeguard here: approve the cleanup script, and be suspicious of any
other command during a cleanup.

- The AI must not explore your disk on its own (`ls`, `find`, `du`, `Get-ChildItem` and so on).
- The AI must not read the optional deletion log or the script's state folder.
- The AI must not delete anything itself or clean categories you did not approve.

### The `--deep` caveat

The normal scan only looks inside known cache locations. The optional deep scan is different: to find
old `node_modules` folders it walks through your home folder (or a projects folder you name), including
Documents and Desktop. It reads folder structure and modification dates only, never file contents, and
it changes nothing. The names it sees stay inside the script; the AI still receives only counts and
sizes. The deep scan runs only when you ask for it.

### The optional log

If you ask for a record of what was deleted, the script can write a log file on your own computer
(`--log`, off by default). That file does contain paths. The AI is told the log exists and where the
folder is, not what is in it.

## Install

Pick one of the three ways. After installing, restart your AI agent.

### 1. With the skills CLI

Needs Node.js.

```bash
npx skills add awankkaley/disk-cleanup -g
```

`-g` installs it for your user account so it works in every project. Add `-a claude-code` (or `codex`,
`cursor`, `gemini-cli`, ...) to choose agents, or let the CLI ask you.

The skills CLI installs the skill itself, which is all most agents need. The only thing it leaves out is
the small `/disk-cleanup` command file for Gemini CLI and OpenCode (see "How to use"); on those two,
ask in plain words, or use the one-line installer instead.

### 2. One-line installer

macOS (Terminal):

```bash
curl -fsSL https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.1.0/install.sh | bash
```

Windows (PowerShell):

```powershell
irm https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.1.0/install.ps1 | iex
```

The installer downloads release v1.1.0, finds the AI agents on your computer, and copies three things
into each agent's skills folder: `SKILL.md`, `scripts/` and `LICENSE`. For Gemini CLI and OpenCode,
which cannot start a skill with a slash command, it also adds one small command file
(`~/.gemini/commands/disk-cleanup.toml`, `~/.config/opencode/commands/disk-cleanup.md`) that does
nothing but hand over to the skill. If you already have your own command file with that name, the
installer leaves it alone and tells you. It does not run the cleanup, does not need administrator
rights, and writes nowhere else.

To install for specific agents only:

```bash
curl -fsSL https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.1.0/install.sh | bash -s -- --agent claude,cursor
```

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.1.0/install.ps1))) -Agent claude,cursor
```

Agent names: `claude`, `codex`, `cursor`, `gemini`, `copilot`, `opencode`, `amp`, `goose`, `agents`.

### 3. Manual copy

Download the [v1.1.0 release](https://github.com/awankkaley/disk-cleanup/releases/tag/v1.1.0), unpack
it, and copy `SKILL.md`, `scripts/` and `LICENSE` into a folder named `disk-cleanup` at the right
location for your agent:

| Agent | Folder |
| --- | --- |
| Claude Code | `~/.claude/skills/disk-cleanup/` |
| OpenAI Codex CLI | `~/.agents/skills/disk-cleanup/` |
| Cursor | `~/.cursor/skills/disk-cleanup/` |
| Gemini CLI | `~/.gemini/skills/disk-cleanup/` |
| GitHub Copilot CLI | `~/.copilot/skills/disk-cleanup/` |
| OpenCode | `~/.config/opencode/skills/disk-cleanup/` |
| Amp, Goose, and other agents that read the shared folder | `~/.agents/skills/disk-cleanup/` |

On Windows, `~` is your user folder, for example `C:\Users\<you>`.

Optional, for the `/disk-cleanup` command on Gemini CLI or OpenCode: also copy
`commands/gemini/disk-cleanup.toml` to `~/.gemini/commands/`, or `commands/opencode/disk-cleanup.md` to
`~/.config/opencode/commands/`.

## How to use

### Type a command

| Agent | Type this | Deep scan (old `node_modules`) |
| --- | --- | --- |
| Claude Code | `/disk-cleanup` | `/disk-cleanup deep` |
| Cursor | `/disk-cleanup` (pick it from the `/` menu) | `/disk-cleanup deep` |
| GitHub Copilot CLI | `/disk-cleanup` | `/disk-cleanup deep` |
| OpenAI Codex CLI | `$disk-cleanup` (or pick it with `/skills`) | `$disk-cleanup deep` |
| Gemini CLI | `/disk-cleanup` ¹ | `/disk-cleanup deep` |
| OpenCode | `/disk-cleanup` ¹, or `@disk-cleanup` | `/disk-cleanup deep` |
| Goose | `/skills disk-cleanup`, then ask | ask for a deep scan |
| Amp | no command; say "use the disk-cleanup skill" | ask for a deep scan |

¹ Needs the command file that the one-line installer adds. Without it (skills CLI or manual copy), ask
in plain words; the skill works the same.

What you can add after the command:

| You type | What happens |
| --- | --- |
| nothing | Scans and shows the table. |
| `deep` | Also looks for old `node_modules` folders, grouped by how long they have been untouched. |
| `help` | Explains the skill and these options. Runs nothing. |

There is no option that cleans straight away, on purpose. Even `/disk-cleanup clean all` scans first,
shows you the table, and waits for you to choose.

### Or just ask

Ask in plain words, in any agent. For example:

- "My disk is almost full. Help me free up some space."
- "Clean up junk files on this laptop."
- "How much space can I get back by clearing caches?"
- "Find old node_modules folders I can delete."
- "Also empty the trash."

The assistant scans, shows a table, and waits for your choice. A typical exchange:

> **You:** My disk is almost full.
>
> **Assistant:** I scanned your Mac. About 14.2 GB can be freed safely:
>
> | Item | Size | Risk | What you will notice |
> | --- | --- | --- | --- |
> | Xcode derived data | 6.1 GB | safe | The next build takes longer. |
> | Chrome cache | 3.4 GB | safe | Pages load slightly slower once. |
> | npm cache | 2.2 GB | safe | Packages are downloaded again when needed. |
> | ... | | | |
>
> Safari cache was skipped because Safari is open. Shall I clean the recommended items?
>
> **You:** Yes, all except Xcode.

Your agent will ask permission to run the script. That is expected. It should not need to run any other
command for the cleanup.

## What gets cleaned

Risk levels: **safe** means the app rebuilds it on its own; **rebuild needed** means you have to run a
command to get it back; **irreversible** means it is gone for good.

| Category id | What it is | Platform | Risk |
| --- | --- | --- | --- |
| `app-caches` | Application caches | macOS, Windows | safe |
| `temp-files` | Temporary files older than 7 days | macOS, Windows | safe |
| `logs` | Log files and crash reports older than 7 days | macOS | safe |
| `crash-dumps` | Application crash dumps | Windows | safe |
| `thumbnail-cache` | Explorer thumbnail and icon cache | Windows | safe |
| `store-app-caches` | Microsoft Store app caches (temporary files and internet cache only) | Windows | safe |
| `trash` | Trash / Recycle Bin (only when you explicitly ask) | macOS, Windows | irreversible |
| `browser-chrome` | Chrome cache | macOS, Windows | safe |
| `browser-edge` | Edge cache | macOS, Windows | safe |
| `browser-firefox` | Firefox cache | macOS, Windows | safe |
| `browser-brave` | Brave cache | macOS, Windows | safe |
| `browser-opera` | Opera cache | macOS, Windows | safe |
| `browser-arc` | Arc cache | macOS, Windows | safe |
| `browser-safari` | Safari cache | macOS | safe |
| `npm-cache` | npm cache | macOS, Windows | safe |
| `yarn-cache` | Yarn cache | macOS, Windows | safe |
| `pnpm-store` | Unused packages in the pnpm store | macOS, Windows | safe |
| `pip-cache` | pip cache | macOS, Windows | safe |
| `gradle-cache` | Gradle caches | macOS, Windows | safe |
| `cargo-cache` | Cargo registry cache | macOS, Windows | safe |
| `go-cache` | Go build cache | macOS, Windows | safe |
| `docker-dangling` | Dangling Docker images | macOS, Windows | safe |
| `homebrew-cache` | Homebrew downloads | macOS | safe |
| `cocoapods-cache` | CocoaPods cache | macOS | safe |
| `xcode-derived-data` | Xcode build cache | macOS | safe |
| `xcode-device-support` | Xcode device support files unused for 90+ days | macOS | safe |
| `xcode-simulators-unavailable` | Simulators Xcode can no longer use | macOS | safe |
| `node-modules-stale` | `node_modules` in idle projects (deep scan only) | macOS, Windows | rebuild needed |

Deletion is permanent. Cleaned items are not moved to the Trash or Recycle Bin.

For browsers, only the cache is removed. On Windows, `app-caches` covers a fixed list of known apps
(Slack, Discord, Teams, Spotify, VS Code), and `store-app-caches` covers only each Store app's
`TempState` and `INetCache` folders; `LocalCache` is left alone.

For `pnpm-store` the scan shows no size. pnpm only removes packages that no project uses any more, so
the amount freed is known only after cleaning.

A developer tool whose cache was moved to a non-standard place shows as unavailable and is skipped.
Clean it with the tool's own command if you want to.

A `node_modules` folder counts as stale only if the project has a `package.json` and a lockfile (so it
can be restored with one install command) and nothing in the project has been modified for at least 30
days. You choose the threshold.

### What is never touched

- Documents, Desktop, Downloads, Pictures, Movies, Music, and cloud-drive folders (iCloud, OneDrive,
  Dropbox, Google Drive).
- Browser cookies, history, saved passwords, sessions, bookmarks and extensions.
- Xcode Archives, Docker volumes and tagged images, the Go module cache.
- Anything that needs administrator rights.
- Caches of apps that are currently open.

## Manual CLI usage

You can run the script yourself, without an AI. Output is JSON.

macOS:

```bash
bash scripts/cleanup.sh scan
bash scripts/cleanup.sh clean --token <token> --categories npm-cache,browser-chrome
```

Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\cleanup.ps1 scan
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\cleanup.ps1 clean --token <token> --categories npm-cache,browser-chrome
```

| Command | Options |
| --- | --- |
| `scan` | `--deep` also look for stale `node_modules` (slow). `--min-age-days N` age limit for temp files and logs, default 7. `--projects-dir PATH` where the deep scan looks, default your home folder. |
| `clean` | `--token ID` from the scan (required). `--categories id1,id2` (required). `--empty-trash` needed for `trash`. `--min-idle-days N` for `node-modules-stale`, default and minimum 30. `--log` write a local list of deleted paths. |
| `--help`, `--version` | |

A scan token is valid for 15 minutes and for one clean.

## Optional: Full Disk Access on macOS

macOS protects some folders, including Safari's cache. Without extra permission the Safari category
shows as "no permission" and is skipped. Everything else still works.

If you want Safari's cache included, open System Settings > Privacy & Security > Full Disk Access and
enable the terminal app your AI agent runs in. This gives that terminal, and everything running in it,
access to much more of your disk, so only do it if you are comfortable with that. The skill never asks
for it and never changes it.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.1.0/install.sh | bash -s -- --uninstall
```

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.1.0/install.ps1))) -Uninstall
```

If you installed with the skills CLI: `npx skills remove disk-cleanup -g`. If you copied it by hand,
delete the `disk-cleanup` folder from your agent's skills folder.

`install.sh` only replaces or removes a `disk-cleanup` folder that really is this skill (its `SKILL.md`
says `name: disk-cleanup`). If it finds a different folder with that name it stops and changes nothing.
The same care applies to the Gemini CLI and OpenCode command files: uninstall removes them only when
they carry the installer's marker line, so a `disk-cleanup` command you wrote yourself stays.

The script keeps a small state folder (the last scan token and any logs you asked for). You can delete
it too: `~/Library/Application Support/disk-cleanup` on macOS, `%LOCALAPPDATA%\disk-cleanup` on Windows.

## FAQ

**Is it safe?**
The recommended categories are caches and temporary files that apps recreate on their own. The worst
you should notice is an app or a build being slower the first time afterwards. Anything riskier is
labelled and is never selected by default.

**Can I undo a cleanup?**
No. Files are deleted, not moved to the Trash. That is why the skill only targets things that can be
rebuilt, and why emptying the trash needs your explicit yes.

**Can the AI see my file names?**
Not through this skill; the script only reports totals. The skill also instructs the AI not to look
around on its own, but that part is an instruction, not a lock. See "Privacy guarantees".

**Why was a category skipped?**
Usually because the app is open (close it and ask for a new scan), because the tool is not installed,
because macOS denied access (see Full Disk Access), or because a developer tool keeps its cache in a
non-standard place, which the script will not touch.

**It freed less than the scan promised.**
Some files are in use or protected and cannot be removed; those are reported as "partial". Apps also
start refilling their caches immediately.

**Does it work on Linux?**
No. The installer will copy the skill, but the script only supports macOS and Windows.

**Will it log me out of websites?**
No. Cookies, sessions and saved passwords are not touched, only the browser cache.

**Why does it not find my big files?**
Listing large files would show your file names to the AI. Use Finder (macOS: Apple menu > About This
Mac > More Info > Storage Settings) or Windows Settings > System > Storage for that.

## Contributing

Issues and pull requests are welcome. The rules that matter most:

- The script output must never contain a path, a file name, a username or any other runtime string.
  Labels and messages are fixed constants.
- Every deletion goes through the single guarded delete routine.
- `scripts/cleanup.sh` must run on the bash 3.2 that ships with macOS; `scripts/cleanup.ps1` must run
  on Windows PowerShell 5.1. No extra dependencies.

**Adding a Windows app to `app-caches`.** `scripts/cleanup.ps1` contains a data table of known apps.
Add one row with the app's process name and its cache folder under `%APPDATA%` or `%LOCALAPPDATA%`.
Only `Cache`, `Code Cache`, `GPUCache` and `CachedData` subfolders are allowed. Add a test in `tests/`
that shows the cache is removed and a neighbouring non-cache file is kept.

**Adding a category.** Add it to the category list in both scripts where the concept exists on both
platforms, with a stable id, a fixed label and impact text, and a risk level. Prefer the tool's
official clean command. Add tests for: size reporting, cleaning, the skipped states, and the privacy
check. Then add a row to the tables in `SKILL.md`, `README.md` and `README.id.md`.

**Running the tests.** Tests use a fake home folder and stubbed tools; they never touch your real files.

```bash
brew install bats-core shellcheck
shellcheck -s bash install.sh scripts/cleanup.sh scripts/lib/*.sh
bats tests/
```

```powershell
Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser
Invoke-Pester -Path tests
```

To try the installer from a checkout without downloading: `./install.sh --local .` (the checkout must
not be the installed copy itself; the installer refuses when source and destination overlap).

## Licence

[MIT](LICENSE) © 2026 awankkaley
