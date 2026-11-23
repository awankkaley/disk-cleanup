# disk-cleanup

**English** | [Bahasa Indonesia](README.id.md)

disk-cleanup lets the AI assistant on your computer free up disk space on a Mac or Windows laptop
without ever seeing your files. It clears the junk that apps leave behind, and it lets you, and only
you, pick big files and old downloads to throw away.

**Who it is for:** anyone whose laptop says "storage almost full". You do not need to know how to
code. If you can chat with an AI app and click "Allow", you can use it.

## What you'll see

1. You tell your AI app: "My laptop is full, help me free up space."
2. The app asks permission to run the cleanup script. You allow it.
3. A few seconds later you get a short list, for example:

   > About 14 GB can be freed safely.
   >
   > | What | Size | What you will notice |
   > | --- | --- | --- |
   > | Chrome temporary files | 3.4 GB | Pages load slightly slower once. |
   > | Apps' temporary files | 6.1 GB | Apps rebuild them when needed. |
   > | Old iPhone update installers | 4.7 GB | Downloaded again if ever needed. |
   >
   > Shall I clean these?

4. You answer "yes", or "everything except Chrome". Only what you chose is cleaned.
5. Still short of space? Ask to review your big files. A page opens in your own browser with your
   largest files and old downloads. You tick what can go and press "Save selection"; those files move
   to the Trash. The AI never sees that page.

Nothing is ever cleaned before you have seen the list and said yes.

## Which app do I need?

The skill runs a small script **on your own computer**, so it only works in AI apps that can do
that. Chat websites and phone apps cannot: they run code on the company's servers, where your disk
does not exist.

| App | Does it work? | Notes |
| --- | --- | --- |
| **Claude desktop app, Code tab** (Mac, Windows) | **Yes** | The easiest option. Needs a paid Claude plan (Pro or higher). Use a "Local" session. |
| **ChatGPT desktop app** (the app that includes Codex; Mac, Windows) | **Yes** | Runs commands on your computer, with limits: it will ask for approval because the files to clean are outside your project folder. |
| **Cursor** (Mac, Windows) | **Yes** | A code editor with an AI agent. Has a free tier with limited use. |
| Claude Code, Codex CLI, GitHub Copilot CLI, Gemini CLI, OpenCode | Yes | Terminal tools for developers. See [For developers](#for-developers). |
| Claude desktop app, **Chat** tab; claude.ai website; Claude phone app | **No** | Skills run in a sandbox on Anthropic's side. It cannot reach your disk. |
| Claude desktop app, **Cowork** | **No** | Works in an isolated environment and only sees folders you connect, not the places where junk lives. |
| chatgpt.com website; ChatGPT phone app | **No** | Cloud tasks run without access to your local files. |
| Gemini app, Gemini website | **No** | We found no documented way for it to run a script on your computer. |

This table follows each company's own documentation as of November 2026 (links at the
[bottom](#sources-for-the-app-table)). Apps change quickly; if yours can run a command on your
computer and supports "Agent Skills", it should work.

Only macOS and Windows are supported. Not Linux, phones or tablets.

## Install

After installing, start a new chat (or restart the app) so the app notices the skill.

### Claude desktop app (recommended)

You need the Claude desktop app ([download links](https://code.claude.com/docs/en/desktop-quickstart))
and a paid Claude plan.

**Way 1: upload a file, no Terminal needed**

1. Download [`disk-cleanup.zip`](https://github.com/awankkaley/disk-cleanup/releases/download/v1.2.0/disk-cleanup.zip).
   Do not unpack it.
2. In the Claude desktop app, open **Customize**, then **Skills**.
3. Use the **+** button to upload a skill, and choose the `disk-cleanup.zip` you downloaded. If Claude
   asks you to turn on "Code execution and file creation", do so under Settings > Capabilities.
4. Find **disk-cleanup** in the list and turn it on.
5. Click the **Code** tab at the top of the sidebar. Under the message box, click the first control
   and choose the top entry under **Local**. Then choose **Open folder…** and pick any folder, for
   example a new empty folder. The cleanup does not use that folder; the app just needs one.
6. Type: `My laptop is almost full, help me free up space.`

Use the **Code** tab, not Chat or Cowork. The skill shows up there too, but it cannot reach your
disk from those tabs and will tell you so.

**Way 2: paste one line**

1. Open Terminal (Mac: press Command+Space, type `Terminal`, press Enter) or PowerShell (Windows:
   click Start, type `PowerShell`, press Enter).
2. Copy the line for your computer, paste it into that window and press Enter.

   Mac:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.2.0/install.sh | bash -s -- --agent claude
   ```

   Windows:

   ```powershell
   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.2.0/install.ps1))) -Agent claude
   ```

3. When it says "Done", close the window, restart the Claude app, and continue from step 5 above.

The installer only copies the skill into Claude's skills folder. It does not clean anything and does
not ask for a password.

### ChatGPT desktop app (Codex)

1. Open Terminal or PowerShell as described above.
2. Paste the line for your computer and press Enter.

   Mac:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.2.0/install.sh | bash -s -- --agent codex
   ```

   Windows:

   ```powershell
   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.2.0/install.ps1))) -Agent codex
   ```

3. Restart the app. In a local chat, type `@`, pick **disk-cleanup**, or simply ask: "My laptop is
   full, help me free up space."
4. When the app asks to approve the cleanup script, approve it. The script works outside your
   project folder, so the app's default permissions make it ask.

### Cursor

Same steps as for ChatGPT, with `cursor` in place of `codex` at the end of the line. Then open
Cursor's Agent chat, type `/`, and pick **disk-cleanup**.

### More than one app, or another app

Leave out the last part and the installer sets the skill up for every supported AI app it finds:

```bash
curl -fsSL https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.2.0/install.sh | bash
```

```powershell
irm https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.2.0/install.ps1 | iex
```

Developers: `npx skills add`, the Claude Code plugin and manual copying are under
[Other ways to install](#other-ways-to-install).

## How to use

### Just ask

You do not need to remember any command. Open your AI app and type what you want, in your own
language:

- "My laptop is almost full. Help me free up some space."
- "Free up 10 GB."
- "How much space could I get back? Don't delete anything yet."
- "Show me my biggest files and old downloads so I can pick what to throw away."
- "Also empty the Trash."

The assistant will ask your permission to run the cleanup script. That is expected: say yes. It
should not need to run any other command for a cleanup, so be wary if it asks to.

### Or type a command

Type `/disk-cleanup`, optionally followed by one word:

| You type | What happens |
| --- | --- |
| `/disk-cleanup` | Checks what can be cleaned, shows you a list with sizes, then asks what you want cleaned. |
| `/disk-cleanup 10gb` | The same, but it proposes the smallest set of safe items that frees that much. It still asks first. |
| `/disk-cleanup scan-only` | Shows the list and the total, then stops. Nothing is cleaned. |
| `/disk-cleanup review` | Opens a private page in your browser with your large files and old downloads, so you can pick what goes to the Trash. See the next section. |
| `/disk-cleanup deep` | For developers: also looks for old `node_modules` folders in projects you have not touched for months. |
| `/disk-cleanup help` | Explains the options. Runs nothing. |

In the ChatGPT desktop app there is no slash command: type `@`, pick disk-cleanup, and add the word
after it (or just ask in plain words). Other apps differ slightly; see
[Commands in each app](#commands-in-each-app).

There is no option that cleans straight away, on purpose. Even `/disk-cleanup clean all` checks
first, shows you the list, and waits for you to choose.

## Review: your large files and old downloads

Temporary files are rarely what fills a laptop. Usually it is a few big videos, old installers and
a Downloads folder nobody has looked at in years. Only you can decide which of those can go, so
this part is done by you, not by the AI.

1. Ask "show me my biggest files and old downloads", or type `/disk-cleanup review`.
2. A page opens in your browser. It lists files of 100 MB or more anywhere in your home folder, and
   files in Downloads that have not been changed for 90 days or more, with name, folder, size and
   date. You can sort by size and filter by group.
3. Tick what you no longer need. The page shows a running total ("selected: 12 items, 8.4 GB").
4. Press **Save selection**. Your browser saves a small file named `disk-cleanup-selection.json`
   into your Downloads folder. Leave it there.
5. Go back to the AI app and say "done".
6. The files you ticked are moved to the Trash (macOS) or Recycle Bin (Windows). The assistant tells
   you how many files and how much space.

Things worth knowing:

- **The AI cannot see the page.** The page is a file on your own computer that your browser opens
  directly. It is never sent to the AI or anywhere else; the page loads nothing from the internet.
  The assistant is told only how many items were found and their total size, and afterwards how
  many were moved. The saved selection file holds two codes and item numbers, no file names.
- **Nothing is deleted from the page.** Ticking and saving does nothing by itself. Files move only
  after you say "done" in the chat.
- **You can get files back.** They are in the Trash or Recycle Bin. On a Mac, open the Trash and
  drag the file back out, or right-click it and choose "Put Back" when macOS offers that. On
  Windows, open the Recycle Bin, right-click the file and choose "Restore".
- **Space is freed only when the Trash is emptied.** Empty it yourself, or ask the assistant to
  ("empty the Trash too"). Emptying is permanent and removes everything in the Trash.
- **Cloud folders: be careful.** If a file is in a folder synced with iCloud Drive, OneDrive,
  Dropbox or Google Drive, moving it to the Trash also removes it from the cloud and from your other
  devices. Files that exist only in the cloud (not downloaded to this computer) are not listed,
  because removing them would free no space here.
- **A changed file is left alone.** If a file was modified, moved or replaced after the page was
  made, it is skipped.
- **The page is good for one hour** and for one use. After that, ask for a new review. An expired
  page and the list behind it are deleted automatically the next time the skill runs.
- **Never listed:** anything inside apps, the system `Library` or `AppData` folders, hidden
  folders, and libraries that macOS shows as a single item, such as your Photos library.

### macOS will ask for permission

The first time, macOS may show a message like **"Claude" would like to access files in your
Downloads folder** (the name is the app your assistant runs in), and the same for Documents and
Desktop.

- Click **Allow** to include that folder in the review.
- Click **Don't Allow** to leave it out. The review still works for the rest.
- To change your answer later: System Settings > Privacy & Security > Files and Folders.

If the page does not open by itself, the assistant tells you where it is so you can open it yourself:
`~/Library/Application Support/disk-cleanup/review.html` on macOS (in Finder: Go > Go to Folder, then
paste the folder part), or `%LOCALAPPDATA%\disk-cleanup\review.html` on Windows (paste it into the
File Explorer address bar).

## Privacy guarantees

There are two kinds of promises here, and they are not equally strong. Please read both.

### Enforced by the script

These hold no matter what the AI does, because the script is written that way and the tests check it.

- **The script only prints totals.** Everything the script hands to the AI is one JSON document with
  category names, sizes, counts and statuses. It never prints file names, folder names, paths, your
  username, your computer name or project names. Error messages are fixed texts with nothing
  inserted into them. This is true for the review as well: the AI gets item counts and sizes only.
- **Fixed list of locations for cleaning.** The cleaner can only clean the categories listed below.
  There is no "clean everything" mode and no way to pass it a folder to delete.
- **Personal files only from the review list, and only to the Trash.** A personal file is moved only
  if a saved selection names it, it was in the list of that review, it still fits the rule it was
  listed under (still that large, or still an old file directly in Downloads), it is still the same
  file (same size and date), and it is inside your home folder outside the protected locations. It
  is moved to the Trash or Recycle Bin, never deleted permanently, whatever goes wrong. What the
  script can **not** prove is that the selection was really saved by you: see
  [Who saved the selection](#who-saved-the-selection) below.
- **Guarded deletion.** Every permanent deletion goes through one routine that refuses anything
  outside your home folder, anything too close to the top of it, any folder that contains a
  protected folder, and any symbolic link. Links are never followed.
- **Developer tools are asked first.** Before a tool's own clean command (npm, Yarn, pnpm, pip, Go,
  Homebrew) may run, the script asks the tool where its cache is. If that is not the tool's standard
  location, the category is reported as unavailable and nothing is run or deleted.
- **The home folder cannot be swapped.** On macOS the script looks up your account's real home folder
  itself and refuses to run when `HOME` points at a folder inside it.
- **Check first, then clean.** Cleaning only works with a code from a check made in the last 15
  minutes, only for categories that check reported, and the code works once. The Trash is emptied
  only with an extra explicit flag. The review has its own one-hour, single-use code.
- **No sudo, no administrator rights.** The script never elevates, never closes your apps, and never
  changes permissions. If an app is open, its temporary files are skipped.
- **No network.** The script sends nothing anywhere, and the review page loads nothing from the
  internet. (Some developer tools' own clean commands are called, such as `npm cache clean`; they
  work locally.)

### Instructions to the AI, not technically enforceable

The skill tells the AI to follow these rules. A well-behaved assistant will, but the script cannot
stop an assistant that has general access to your computer from doing something else. Your AI app's
own permission prompts are the real safeguard: approve the cleanup script, and be suspicious of any
other command during a cleanup.

- The AI must not explore your disk on its own (`ls`, `find`, `du`, `Get-ChildItem` and so on).
- The AI must not open the review page, the list behind it, or your saved selection.
- The AI must not create or change a selection file. Only your own click on "Save selection" counts.
- The AI must not ask you to paste file names, and must not pick files for you.
- The AI must not read the optional deletion log or the script's state folder.
- The AI must not delete anything itself or clean categories you did not approve.

### Who saved the selection

The script cannot see who clicked. What it does instead:

- Each review gets a second, longer code (the selection secret). The script never prints it, so the
  AI is never given it. It exists only inside the review page and the list behind it, and the page
  writes it into the file that "Save selection" saves. A selection file without the right secret is
  refused and nothing is moved.
- The list behind the page carries a checksum. If the list was changed after the review, nothing is
  moved. Each file is also checked again against the rule it was listed under.

What this does **not** guarantee: the assistant runs as your user account, so it is technically able
to read the page or the list, take the secret, and write a selection file itself. The skill forbids
exactly that, so doing it is an open breach of the rules and not something that can happen by
accident, but it is a rule, not a lock. Your AI app's permission prompts are the real barrier: during
a review, the only commands to approve are `review` and `review-apply`.

### Files that do contain your file names

Be clear about this: while a review is open, two files on your disk hold the names and locations of
the listed files: the page itself (`review.html`) and the list behind it. They sit in the script's
state folder, readable only by your own user account. They are removed when your selection is
applied, when a new review replaces them, and, if you never finish the review, the next time any
disk-cleanup command runs after the review is more than an hour old. If the skill is never run
again, they stay until you delete the state folder (see [Uninstall](#uninstall)). The AI is
instructed not to read them; it is **not technically prevented** from doing so, because the
assistant runs as you.

The same goes for the optional deletion log: if you ask for a record of what was cleaned, the script
writes a log file on your own computer (`--log`, off by default). That file contains paths. The AI is
told the log exists and where the folder is, not what is in it.

### The deep scan and the review walk your home folder

The normal check only looks inside known locations of temporary files. Two optional modes go
further, and only when you ask for them: the review, and the developer deep scan for old
`node_modules`. Both walk through your home folder, including Documents and Desktop. They read
names, sizes and dates only, never file contents, and they change nothing. What they see stays
inside the script (and, for the review, the page that only you open).

## What gets cleaned

**Safe to clean** (things apps recreate on their own):

- Apps' temporary files, including those of Slack, Discord, Microsoft Teams (classic) and VS Code.
  Only their temporary files: never messages, settings or downloads.
- Browser temporary files for Chrome, Edge, Firefox, Brave, Opera, Arc and Safari. Only the cache:
  you stay logged in everywhere.
- Temporary files and old logs older than 7 days.
- On a Mac: downloaded iPhone and iPad update installers. Never your device backups.
- On Windows: crash dumps, the thumbnail cache, Microsoft Store apps' temporary files.
- Developer tools' downloads and build leftovers (npm, pip, Homebrew, Xcode, Docker and more), shown
  only if you have them.

What is cleaned here is deleted permanently, not moved to the Trash. That is why this part only
covers things that come back by themselves.

**Only when you say so:**

- The Trash / Recycle Bin: emptied only when you explicitly ask.
- Your own large files and old downloads: only the ones you ticked in the review page, and they
  are only moved to the Trash.
- Old `node_modules` folders (developers, deep scan).

The full list with ids is in [Categories](#categories).

### What is never touched

- Your personal files in Documents, Desktop, Downloads, Pictures, Movies, Music and cloud-drive
  folders (iCloud, OneDrive, Dropbox, Google Drive), with one exception: files **you ticked
  yourself** in the review page, and those are only moved to the Trash.
- Browser cookies, history, saved passwords, sessions, bookmarks and extensions.
- Chat messages, app settings, photo libraries, device backups.
- Xcode Archives, Docker volumes and tagged images, the Go module cache.
- Anything that needs administrator rights.
- Temporary files of apps that are currently open.

## FAQ

**Is it safe?**
The recommended items are temporary files that apps recreate on their own. The worst you should
notice is an app being slower the first time afterwards. Anything riskier is labelled and is never
selected by default. Your own files are only ever touched if you ticked them yourself.

**Can I undo a cleanup?**
Temporary files: no, they are deleted, which is why only things that rebuild themselves are
targeted. Files from the review: yes, they are in the Trash or Recycle Bin until you empty it.

**Can the AI see my file names?**
Not through this skill; the script only reports totals, and the review page is opened by your
browser, not by the AI. The skill also instructs the AI not to look around on its own or open the
review files, but that part is an instruction, not a lock. See [Privacy guarantees](#privacy-guarantees).

**I pressed "Save selection" and said "done", but the assistant cannot find my selection.**
Your browser saved the file somewhere other than Downloads, or asked where to save and you
cancelled. Press "Save selection" again and save it in your Downloads folder with the name it
suggests.

**I freed files with the review but my free space did not change.**
They are in the Trash. Space comes back when you empty it.

**Why was something skipped?**
Usually because the app is open (close it and ask again), because macOS denied access, or because
a developer tool keeps its files in a non-standard place, which the script will not touch.

**It freed less than it promised.**
Some files are in use or protected and cannot be removed. Apps also start refilling their temporary
files immediately.

**Will it log me out of websites?**
No. Cookies, sessions and saved passwords are not touched.

**Does it find duplicate files or clean up my photos?**
No. That would need the AI to read your file names. The review shows large files and old
downloads, and you decide.

**Does it work on Linux, phones or tablets?**
No. macOS and Windows computers only.

## Uninstall

- Uploaded to the Claude desktop app: open Customize > Skills, open disk-cleanup, and turn it off or
  remove it there.
- Claude Code plugin: `claude plugin uninstall disk-cleanup@awankkaley-disk-cleanup`, then
  `claude plugin marketplace remove awankkaley-disk-cleanup`.
- Installed with the one-line installer:

  ```bash
  curl -fsSL https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.2.0/install.sh | bash -s -- --uninstall
  ```

  ```powershell
  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.2.0/install.ps1))) -Uninstall
  ```

- Installed with the skills CLI: `npx skills remove disk-cleanup -g`.
- Copied by hand: delete the `disk-cleanup` folder from your agent's skills folder.

The installer only replaces or removes a `disk-cleanup` folder that really is this skill (its
`SKILL.md` says `name: disk-cleanup`), and only command files that carry its own marker line.
Anything else with the same name is left alone.

The script keeps a small state folder (the last codes, an unfinished review, and any logs you asked
for). You can delete it: `~/Library/Application Support/disk-cleanup` on macOS,
`%LOCALAPPDATA%\disk-cleanup` on Windows.

---

# For developers

## Commands in each app

| Agent | Scan, then choose | Report only | Review files | Deep scan |
| --- | --- | --- | --- | --- |
| Claude Code, plugin | `/disk-cleanup:scan` | `/disk-cleanup:scan-only` | `/disk-cleanup:review` | `/disk-cleanup:deep` |
| Claude desktop (Code tab) and Claude Code, skill | `/disk-cleanup` | `/disk-cleanup scan-only` | `/disk-cleanup review` | `/disk-cleanup deep` |
| ChatGPT desktop app (Codex) | `@`, pick disk-cleanup | add `scan-only` | add `review` | add `deep` |
| Codex CLI | `$disk-cleanup` | `$disk-cleanup scan-only` | `$disk-cleanup review` | `$disk-cleanup deep` |
| Cursor | `/disk-cleanup` | `/disk-cleanup scan-only` | `/disk-cleanup review` | `/disk-cleanup deep` |
| GitHub Copilot CLI | `/disk-cleanup` | `/disk-cleanup scan-only` | `/disk-cleanup review` | `/disk-cleanup deep` |
| Gemini CLI ¹ | `/disk-cleanup:scan` | `/disk-cleanup:scan-only` | `/disk-cleanup:review` | `/disk-cleanup:deep` |
| OpenCode ¹ | `/disk-cleanup/scan` | `/disk-cleanup/scan-only` | `/disk-cleanup/review` | `/disk-cleanup/deep` |
| Goose, Amp | ask in plain words | ask for a report only | ask to review large files | ask for a deep scan |

¹ Needs the command files that the one-line installer adds. They also include a plain `/disk-cleanup`
that takes the same words as the standalone skill, and a `help` command. Without them, ask in plain
words; the skill works the same.

The plugin also has `/disk-cleanup:help`. A size works after any scan command: `/disk-cleanup 10gb`,
`/disk-cleanup:scan 10gb`.

## Other ways to install

### skills CLI

Needs Node.js.

```bash
npx skills add awankkaley/disk-cleanup -g
```

`-g` installs it for your user account. Add `-a claude-code` (or `codex`, `cursor`, `gemini-cli`, ...)
to choose agents, or let the CLI ask you. It installs the skill itself; the `/disk-cleanup` command
files for Gemini CLI and OpenCode come only with the one-line installer.

### One-line installer options

The installer downloads release v1.2.0, finds the AI agents on your computer, and copies `SKILL.md`,
`scripts/` and `LICENSE` into each agent's skills folder. For Gemini CLI and OpenCode it also adds
small command files (`disk-cleanup.toml` plus a `disk-cleanup/` folder with one file per mode in
`~/.gemini/commands/`, and the same with `.md` files in `~/.config/opencode/commands/`). It does not
run the cleanup, does not need administrator rights, and writes nowhere else.

For specific agents only:

```bash
curl -fsSL https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.2.0/install.sh | bash -s -- --agent claude,cursor
```

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.2.0/install.ps1))) -Agent claude,cursor
```

Agent names: `claude`, `codex`, `cursor`, `gemini`, `copilot`, `opencode`, `amp`, `goose`, `agents`.

### Claude Code plugin from the terminal

```text
/plugin marketplace add awankkaley/disk-cleanup
/plugin install disk-cleanup@awankkaley-disk-cleanup
```

Or from your shell: `claude plugin marketplace add awankkaley/disk-cleanup`, then
`claude plugin install disk-cleanup@awankkaley-disk-cleanup`. On Claude Code 2.1.275 or later one step
is enough: `/plugin install disk-cleanup --marketplace awankkaley/disk-cleanup`.

The plugin gives one command per mode (`/disk-cleanup:scan`, `:scan-only`, `:review`, `:deep`,
`:help`); the standalone skill gives a single `/disk-cleanup [scan-only|review|deep|help|10gb]`. Both
follow the same instructions and run the same script. If you install both, Claude Code shows the
skill twice, so pick one.

### Manual copy

Download the [v1.2.0 release](https://github.com/awankkaley/disk-cleanup/releases/tag/v1.2.0), unpack
it, and copy `SKILL.md`, `scripts/` and `LICENSE` into a folder named `disk-cleanup`:

| Agent | Folder |
| --- | --- |
| Claude Code | `~/.claude/skills/disk-cleanup/` |
| ChatGPT desktop app (Codex), Codex CLI | `~/.agents/skills/disk-cleanup/` |
| Cursor | `~/.cursor/skills/disk-cleanup/` |
| Gemini CLI | `~/.gemini/skills/disk-cleanup/` |
| GitHub Copilot CLI | `~/.copilot/skills/disk-cleanup/` |
| OpenCode | `~/.config/opencode/skills/disk-cleanup/` |
| Amp, Goose, and other agents that read the shared folder | `~/.agents/skills/disk-cleanup/` |

On Windows, `~` is your user folder, for example `C:\Users\<you>`.

Optional, for the `/disk-cleanup` commands on Gemini CLI or OpenCode: also copy
`commands/gemini/disk-cleanup.toml` and the folder `commands/gemini/disk-cleanup/` to
`~/.gemini/commands/`, or `commands/opencode/disk-cleanup.md` and the folder
`commands/opencode/disk-cleanup/` to `~/.config/opencode/commands/`.

## Categories

Risk levels: **safe** means the app rebuilds it on its own; **rebuild needed** means you have to run a
command to get it back; **irreversible** means it is gone for good.

| Category id | What it is | Platform | Risk |
| --- | --- | --- | --- |
| `app-caches` | Application caches | macOS, Windows | safe |
| `temp-files` | Temporary files older than 7 days | macOS, Windows | safe |
| `logs` | Log files and crash reports older than 7 days | macOS | safe |
| `ios-updates` | Downloaded iPhone, iPad and iPod update installers | macOS | safe |
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

Every category also carries a `rebuild_cost` (1 nothing noticeable, 2 re-downloaded or rebuilt on
next use, 3 a long re-download or rebuild), which orders the suggestion of `scan --target-gb`.

`app-caches` covers the system cache folder plus a fixed table of four known apps (Slack, Discord,
Microsoft Teams classic, VS Code), and for those only folders named `Cache`, `Code Cache`,
`GPUCache` or `CachedData`. Apps that keep downloads in a cache-named folder (Spotify's offline
music, for example) are deliberately not in the table. An app that is running is skipped. On Windows, `store-app-caches` covers only each Store app's `TempState` and `INetCache`
folders; `LocalCache` is left alone. `ios-updates` never touches device backups.

For `pnpm-store` the scan shows no size: pnpm only removes packages that no project uses any more,
so the amount freed is known only after cleaning. A developer tool whose cache was moved to a
non-standard place shows as unavailable and is skipped.

A `node_modules` folder counts as stale only if the project has a `package.json` and a lockfile and
nothing in the project has been modified for at least 30 days. You choose the threshold.

## Manual CLI usage

You can run the script yourself, without an AI. Output is JSON.

macOS:

```bash
bash scripts/cleanup.sh scan
bash scripts/cleanup.sh scan --target-gb 10
bash scripts/cleanup.sh clean --token <token> --categories npm-cache,browser-chrome
bash scripts/cleanup.sh review
bash scripts/cleanup.sh review-apply --token <review token>
```

Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\cleanup.ps1 scan
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\cleanup.ps1 clean --token <token> --categories npm-cache,browser-chrome
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\cleanup.ps1 review
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\cleanup.ps1 review-apply --token <review token>
```

| Command | Options |
| --- | --- |
| `scan` | `--deep` also look for stale `node_modules` (slow). `--target-gb N` (1 to 10000) add a `suggestion`: the safe categories, cheapest to rebuild first, that reach N GB. `--min-age-days N` age limit for temp files and logs, default 7. `--projects-dir PATH` where the deep scan looks, default your home folder. |
| `clean` | `--token ID` from the scan (required). `--categories id1,id2` (required). `--empty-trash` needed for `trash`. `--min-idle-days N` for `node-modules-stale`, default and minimum 30. `--log` write a local list of deleted paths. |
| `review` | `--min-size-mb N` smallest file listed as large, default 100, minimum 10. `--downloads-age-days N` age of items in Downloads, default 90, minimum 7. Writes the page and opens it; prints counts and a review token. |
| `review-apply` | `--token ID` from the review (required). Reads `disk-cleanup-selection.json` from the Downloads folder, accepts it only with the secret the review page wrote into it, and moves the selected files to the Trash / Recycle Bin. |
| `--help`, `--version` | |

A scan token is valid for 15 minutes and one `clean`. A review token is separate, valid for 60
minutes and one `review-apply`. The review lists at most 500 items, largest first. Every command,
`--help` and `--version` included, first deletes the page and list of a review older than 60 minutes.

## Optional: Full Disk Access on macOS

macOS protects some folders, including Safari's cache. Without extra permission the Safari category
shows as "no permission" and is skipped. Everything else still works.

If you want Safari's cache included, open System Settings > Privacy & Security > Full Disk Access and
enable the app your AI agent runs in. This gives that app, and everything running in it, access to
much more of your disk, so only do it if you are comfortable with that. The skill never asks for it
and never changes it.

## Contributing

Issues and pull requests are welcome. The rules that matter most:

- The script output must never contain a path, a file name, a username or any other runtime string.
  Labels and messages are fixed constants.
- Every permanent deletion goes through the single guarded delete routine. Personal files are only
  ever moved to the Trash, through the single trash routine.
- `scripts/cleanup.sh` must run on the bash 3.2 that ships with macOS; `scripts/cleanup.ps1` must run
  on Windows PowerShell 5.1. No extra dependencies.

**Adding an app to `app-caches`.** Both scripts contain a data table of known apps. Add one row with
the app's process name and its cache folder. Only `Cache`, `Code Cache`, `GPUCache` and `CachedData`
subfolders are allowed. Add a test in `tests/` that shows the cache is removed and a neighbouring
non-cache file is kept.

**Adding a category.** Add it to the category list in both scripts where the concept exists on both
platforms, with a stable id, a fixed label and impact text, a risk level and a rebuild cost. Prefer
the tool's official clean command. Add tests for: size reporting, cleaning, the skipped states, and
the privacy check. Then add a row to the tables in `README.md` and `README.id.md`.

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


## Sources for the app table

Checked in November 2026 against each vendor's documentation:

- Claude desktop Code tab runs locally and loads skills: <https://code.claude.com/docs/en/desktop>, <https://code.claude.com/docs/en/desktop-quickstart>
- Uploading a skill as a ZIP, and skills in chat running in a sandbox: <https://claude.com/docs/skills/how-to>, <https://claude.com/docs/skills/overview>
- Cowork's isolated environment: <https://support.claude.com/en/articles/13345190-get-started-with-claude-cowork>
- ChatGPT desktop app and Codex skills, permissions: <https://learn.chatgpt.com/docs/build-skills>, <https://learn.chatgpt.com/docs/permission-modes>
- ChatGPT cloud tasks have no local file access: <https://help.openai.com/en/articles/20001548-agent-security-and-local-work-sync-in-chatgpt>
- Cursor skills and terminal: <https://cursor.com/docs/context/skills>, <https://cursor.com/docs/agent/terminal>
- Gemini CLI skills: <https://geminicli.com/docs/cli/skills/>
- GitHub Copilot skills: <https://docs.github.com/en/copilot/concepts/agents/about-agent-skills>

## Licence

[MIT](LICENSE) © 2026 awankkaley
