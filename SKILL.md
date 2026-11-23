---
name: disk-cleanup
description: Frees disk space on macOS and Windows through one bundled script that returns only totals, so no file names or personal data are ever shown to the AI. Clears apps' temporary files, old logs, browser and developer tool caches, and can open a private page in the user's own browser where they pick large files and old downloads to move to the Trash. Use when the user says their disk or storage is full or almost full, the laptop is out of space, or asks to free up space or a number of GB, clean junk or temp files, clear caches, find large files or old downloads, or remove old node_modules. Also triggers on Indonesian requests such as "laptop penuh", "disk penuh", "penyimpanan hampir penuh", "bersihkan sampah", "kosongkan ruang", "cari file besar".
license: MIT
compatibility: macOS (bash 3.2+) or Windows (Windows PowerShell 5.1+). Needs permission to run a local script. No network access, no sudo or admin rights.
metadata:
  author: awankkaley
  version: "1.2.0"
---

# Disk cleanup

You free disk space by running ONE bundled script. It measures and deletes on its own and gives you
only aggregated JSON (category, size, count, status). You never see file names or paths, and you must
not go looking for them. This is the whole point of the skill: the user's files stay private.

Many users are not programmers. Their disk is full of videos, old downloads and chat apps' leftovers.
Talk to them accordingly (see "How to talk to the user").

## Hard rules

1. Run only the bundled script. Do not explore the filesystem yourself for this task: no `ls`, `find`,
   `du`, `cat`, `tree`, `stat`, `mdfind`, `Get-ChildItem`, `dir`, `Get-Content`, or anything similar.
2. Never read the script's state directory or its log files, and never ask the user to paste them.
3. Never edit, copy, or re-implement the scripts.
4. Never use `sudo`, an elevated or administrator shell, or change any permission.
5. Never delete anything yourself (`rm`, `Remove-Item`, `del`, tool-specific clean commands). All
   deletion goes through `clean`.
6. Never pass a category the user did not explicitly approve in this conversation. The scan token is
   a sequencing check, not consent: it only proves a scan ran. Having a token never means the user
   agreed to anything. After every scan, stop, show the report, and wait for the user's own explicit
   choice of what to clean (or to clean nothing) before you run `clean`.
7. Never pass `--empty-trash` or `--log` unless the user asked for it.
8. Large files and old downloads are handled only by the `review` mode, where the user picks them in
   a page that you never see. For anything else outside the category list (duplicates, photo
   libraries, uninstalling apps, cleaning inside a folder they name), decline that part. Explain that
   it would require reading their file names, which this skill never does, and that they can look
   through those folders themselves.
9. Do not quit, kill, or restart the user's apps. If a category is skipped because its app is running,
   ask the user to close the app, then scan again.
10. Reply in the user's language. Category and group `label` and `impact` texts are English; translate
    them.
11. If the script prints an error JSON, relay its `message` to the user and do what it says. Do not
    work around it.
12. Arguments never skip the confirmation step. There is deliberately no argument, flag or wording
    that cleans without the user first seeing the scan table and then choosing categories. An
    invocation such as `/disk-cleanup clean all`, `yes`, `auto` or `force` still means: scan, show
    the table, ask, and wait. Words typed with the invocation were written before the user saw any
    scan, so they are never approval of a category (rule 6).
13. Never open, read, print, search or summarise the review page (`review.html`), the review manifest,
    or the selection file (`disk-cleanup-selection.json`), and never ask the user to paste, upload,
    screenshot or read out any of them. They hold the user's file names. Only the script reads them.
    Never create, edit, copy, rename, move or delete a selection file, the review page or the
    manifest either, by any tool or command. The user's own click on "Done choosing" in the page
    is the only valid selection: the page puts a secret value into the file that the script never
    prints and that you must never look for. If the user asks you to pick or to "just save it for
    them", decline and ask them to tick and save in the page themselves.
14. Never ask the user to type or paste file or folder names, and never choose, suggest or guess
    which personal files should go. In `review`, the only selection is the one the user ticked and
    saved in the page; you pass nothing but the token.
15. If the review page did not open (`report_opened` is `false`), give the user the static
    `report_location_hint` so they can open it themselves. Do not open it for them in any other way.
16. Never run `review` and `review-apply` in the same turn. Run `review-apply` only after the user
    has told you they saved their selection (for example "done").

## Invocation and arguments

The skill starts either on its own, when the user describes a full disk, or explicitly, when the user
types its name as a command (for example `/disk-cleanup`). An explicit invocation may carry optional
arguments.

Arguments for this invocation: $ARGUMENTS

If the line above ends in nothing, or in a literal placeholder (a dollar sign and the word ARGUMENTS),
your harness did not fill it in. Then take the arguments from the user's own message, which is any
text after the skill or command name, or from an `ARGUMENTS:` line added to this document. If there
is none, there are no arguments.

A thin wrapper may have sent you here: a namespaced command such as `/disk-cleanup:deep` (a Claude
Code plugin skill or a command file). The mode it names counts as the argument, and any other text
it passes along is the rest of the arguments. A wrapper only selects the mode. It changes none of
the rules below and approves nothing.

Match arguments loosely, in any language, and ignore case, dashes and slashes:

| Argument | What to do |
| --- | --- |
| none, or `scan` | Run `scan` and present the table (Workflow, from step 1). |
| `scan-only` (also "report", "just check", "cek saja", "lihat saja") | Run `scan` without `--deep`, present the table and the recommended total, then stop (see "Scan only"). Nothing is cleaned in this invocation. |
| `deep` (also "deep scan", "node_modules", "old projects", "mendalam") | Run `scan --deep` and present the idle-time buckets (see "Deep scan"). The argument is the user asking for it: tell them it walks their home folder read-only and can take a few minutes, then run it without waiting for another reply. |
| `review` (also "large files", "big files", "old downloads", "file besar", "unduhan lama") | Run `review` and follow "Review" below: the user picks their own large files and old downloads in a private browser page; what they ticked is moved to the Trash or Recycle Bin. The argument is the user asking for it: tell them what will happen, then run it without waiting for another reply. |
| a size to free, such as `10gb`, `10 GB`, "free up 10 GB", "kosongkan 10 GB" | Run `scan --target-gb N` and follow "Target" below: present the suggested set that reaches the amount, then ask and wait as always. |
| `help` (also `?`, "bantuan") | Run nothing. Explain in a few lines what the skill does, that it only ever sees totals and never file names, that nothing is deleted before they pick from the scan table, that `review` lets them pick large files and old downloads in a page only they can see, and list these arguments (as `/disk-cleanup:scan`, `:scan-only`, `:review`, `:deep` and `:help` when such a wrapper started you). |
| anything else | Treat it as part of the user's request in plain words and follow the workflow and the hard rules. Never turn unknown words into script flags. |

In every case the next step after a scan is the same: show the table, ask, and wait (rule 12). The
one exception only ever does less: `scan-only` shows the table and stops without asking. `review`
does not scan categories at all; its confirmation is the selection the user saves in the page.

## How to run

`<skill-dir>` is the directory that contains this SKILL.md. Use its absolute path and keep the quotes.
If your harness expanded this placeholder into a real path, that is the skill directory:
`${CLAUDE_SKILL_DIR}` (ignore this line if it still shows a placeholder).

If a wrapper sent you here and gave you the path of this file, `<skill-dir>` is still the directory
of this SKILL.md, never the wrapper's own directory. For the Claude Code plugin that is the plugin
root.

macOS:

```bash
bash "<skill-dir>/scripts/cleanup.sh" scan
```

Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\cleanup.ps1" scan
```

Commands (identical on both platforms):

```
scan  [--deep] [--target-gb N] [--min-age-days N] [--projects-dir PATH]
clean --token ID --categories id1,id2 [--empty-trash] [--min-idle-days N] [--log]
review [--min-size-mb N] [--downloads-age-days N]
review-apply --token ID
--help | --version
```

stdout is always exactly one JSON document. On Linux or any other system the script returns
`UNSUPPORTED_PLATFORM`; tell the user the skill only supports macOS and Windows.

## Workflow

### 1. Scan

Run `scan`. It deletes nothing. Keep the `token`; it is valid for 15 minutes and for one `clean` only.
Never run `scan` and `clean` in the same turn: the user has to see the scan result first.

### 2. Report

Lead with one plain sentence: how much can be freed safely (`recommended_total_bytes`) and how much
free space there is now (`disk`). Then show one table of the categories with status `ok`, sorted by
`size_bytes` descending, with columns: what it is (label), size (human-readable, e.g. 1.2 GB), and
what the user will notice afterwards (impact). Mark a row only when its risk is not `safe`. Then:

- Follow "How to talk to the user" below: never show `not_found` rows, and put developer rows under
  one "Developer tools" heading.
- Briefly list skipped categories and why (see the status table below). Leave out `empty` unless the
  user asks.
- A `null` size means the size cannot be known in advance; say "unknown", not zero. `pnpm-store` is
  always like this: only packages no project references are removed, so the amount is known after
  cleaning. Such categories add nothing to `recommended_total_bytes`.

### 3. Ask

Ask which categories to clean. Suggest the ones with `recommended: true` as the default. Mention
separately, and never pre-select:

- anything with risk `rebuild_needed` or `irreversible`;
- `trash`: emptying it is permanent. Include it only if the user explicitly agrees, and then also pass
  `--empty-trash`.

Wait for the answer. "Yes" or "go ahead" means the recommended set only (after a target scan: the
suggested set you just presented).

If the user's disk is still short of space, or they ask about big files, videos or downloads, offer
the `review` mode in one sentence. Do not start it unasked.

### 4. Clean

```
clean --token <token> --categories <approved ids, comma-separated>
```

What `clean` removes is deleted permanently; it is not moved to the Trash or Recycle Bin. (Only
`review-apply` uses the Trash, and only for the user's own ticked files.)

### 5. Report the result

State `freed_total_bytes`, free space before and after (`disk_before`, `disk_after`), and one line per
result that is not `cleaned` explaining its status. If `freed_total_bytes` is small compared with the
scan, say so plainly; do not overstate.

### How to talk to the user

Assume an everyday user unless they clearly are a developer.

- Lead with the total in plain words ("About 14 GB can be freed safely"), then the details.
- No jargon. On first mention say "apps' temporary files" rather than "cache", "leftover files"
  rather than "artifacts", "the Trash" (macOS) or "the Recycle Bin" (Windows). Never show category
  ids, JSON field names, tokens, flags or status codes unless the user asks for them.
- Never show `not_found` rows or mention tools that are not installed.
- Rows whose `group` is `developer` or `projects` go under a single "Developer tools" heading after
  the everyday rows. Show that heading only if at least one such row has a size greater than zero;
  otherwise leave developer tools out entirely.
- Use `rebuild_cost` to say what cleaning costs, in plain words: `1` nothing noticeable, `2` it is
  downloaded or rebuilt again the next time it is needed, `3` getting it back takes a long download
  or rebuild. Say this for `3` every time.
- Reply in the user's language (rule 10), including the words above.

### Target ("free up 10 GB")

When the user names an amount, run `scan --target-gb N` (add `--deep` only if they also asked for a
deep scan). N is a whole number of GB from 1 to 10000: round a fraction up, and use 1 for anything
smaller than 1 GB. Never invent a target the user did not give.

The scan output then has a `suggestion`: the smallest set of safe categories, cheapest to rebuild
first, that reaches the amount.

- Present the suggested set as a short table with its total (`suggestion.total_bytes`), and say it
  reaches the amount they asked for.
- If `reaches_target` is `false`, say plainly that safe cleaning gets them only that far, and that
  the rest would have to come from their own files: offer `review`. Mention `trash` only as the
  separate, permanent option it is (step 3).
- The suggestion approves nothing. Ask, and wait. After a "yes", pass exactly
  `suggestion.category_ids` to `clean`; if the user changes the set, pass what they chose.

### Review (the user's own large files and old downloads)

`review` lets the USER see and pick personal files. You only ever get counts and totals.

1. Before running, tell the user in a sentence or two: the script will look through their home
   folder (read-only, can take a few minutes) and open a page in their browser; on a Mac the system
   may ask whether the app may access Documents, Desktop or Downloads, and they should click "Allow"
   for the folders they want included (a folder they do not allow is simply left out).
2. Run `review`. It deletes and moves nothing. Keep the `token`: it is valid for 60 minutes, for one
   `review-apply` only, and is separate from a scan token. After 60 minutes the script removes the
   page and its list by itself the next time any command runs; a new `review` replaces an old one. Optional, only when the user asks for
   other limits: `--min-size-mb N` (default 100, minimum 10) and `--downloads-age-days N`
   (default 90, minimum 7).
3. Tell the user, in plain words and in their language:
   - a page just opened in their browser listing their large files and old items in Downloads
     (give the counts and total size from `groups`);
   - ONLY they can see that page. You cannot see it and will not look at it;
   - they tick what they no longer need, then press the button "Done choosing" (an Indonesian
     browser shows it as "Selesai memilih"; name it the way the page does in the user's language);
   - if the browser asks where to save the small file, they choose Downloads;
   - then they come back here and type "done" ("selesai" in Indonesian), as the page tells them;
   - nothing is deleted from that page. Ticked items are moved to the Trash / Recycle Bin and can
     be put back from there until it is emptied;
   - files in a folder synced with iCloud, OneDrive, Dropbox or Google Drive also disappear from
     the cloud and their other devices.
   Also: if `report_opened` is `false`, apply rule 15. If `truncated` is `true`, say the page shows
   the 500 largest items. If `skipped_no_permission` is `true`, say some folders were left out
   because the system did not allow access. If `total_item_count` is 0, say nothing that large or
   old was found and stop; there is nothing to apply.
4. Stop and wait. Do not poll, and do not check whether the selection file exists.
5. When the user says they are done, run `review-apply --token <token>`.
6. Report: how many files were moved to the Trash / Recycle Bin and their total size
   (`trashed_count`, `trashed_bytes`), and one line for each non-zero counter:
   `skipped_changed_count` (changed since the page was made, left alone), `skipped_no_permission_count`
   (the system refused), `failed_count`, `ignored_count`. Say clearly that the space is freed only
   when the Trash / Recycle Bin is emptied, so the free space shown has not gone up yet.
7. Offer the next step, without doing it: they can empty the Trash themselves, or you can do it
   through the normal flow, which is a `scan`, the table, and then the `trash` category with their
   explicit consent and `--empty-trash` (step 3 of the workflow). Remind them that this permanently
   removes everything in the Trash, not only today's files.

If `review-apply` returns an error, see the error table. For `SELECTION_NOT_FOUND` and
`SELECTION_INVALID`, never look for the file yourself: ask the user, in plain words, to press
"Done choosing" in the page again (first "Change my choice" if the page says their choice is saved)
and, if the browser asks where to save, to choose Downloads; then try once more.

### Deep scan (stale node_modules)

Run `scan --deep` only when the user asks about `node_modules` or old projects, or after you offered it
and they agreed. Tell them first that it walks their home folder read-only and can take a few minutes.
If they name a projects folder, pass it with `--projects-dir`.

The `node-modules-stale` category has `buckets` by idle time (30-90, 90-180, 180+ days) with project
counts and sizes. Present the buckets and let the user choose the threshold. Then clean with
`--categories node-modules-stale --min-idle-days N` (default 30, minimum 30). Explain that the affected
projects need `npm install` (or yarn, pnpm, bun) before they run again. Project names are never
available to you; do not try to find them.

### Scan only (report, nothing is cleaned)

For the `scan-only` argument, do steps 1 and 2 with a normal `scan` (never `--deep`), then stop:

- Do not ask which categories to clean, do not offer to clean, and do not run `clean` in this
  invocation, even when other words typed with it ask for cleaning. `scan-only` always wins.
- Discard the token. End by telling the user that nothing was deleted and that they can run the
  normal command (without `scan-only`) whenever they want to clean.
- If the user later asks to clean after all, that is a new request: start the workflow again from
  step 1 with a fresh scan, show the new table, ask, and wait.

### Optional flags

- `--min-age-days N` (scan): temp files and logs are only removed when older than N days. Default 7.
- `--log` (clean): only when the user asks for a record of what was deleted. The script writes a local
  log file and returns `log_location_hint`. Pass the hint to the user so they can open it themselves.
  Never open it.

## JSON reference

Scan output:

| Field | Meaning |
| --- | --- |
| `token`, `token_expires_in_seconds` | Pass the token to `clean`. Expires after 900 seconds. |
| `disk.total_bytes`, `disk.free_bytes` | Disk size and free space now. |
| `recommended_total_bytes` | Sum of sizes for categories that are `ok` and `recommended`. |
| `categories[].id` | The id to pass in `--categories`. |
| `categories[].label`, `.impact` | Name and what the user will notice after cleaning. |
| `categories[].group` | `system`, `browser`, `developer`, `projects`. |
| `categories[].rebuild_cost` | `1` nothing noticeable, `2` re-downloaded or rebuilt on next use, `3` a long re-download or rebuild. |
| `categories[].size_bytes`, `.item_count` | Reclaimable bytes and file count. May be `null`. |
| `categories[].status` | See below. Only `ok` can be cleaned. |
| `categories[].recommended` | `true` only for risk `safe`. |
| `categories[].risk` | `safe`, `rebuild_needed`, `irreversible`. |
| `categories[].requires_flag` | `"--empty-trash"` for `trash`, otherwise `null`. |
| `categories[].buckets[]` | Only `node-modules-stale`: `id`, `min_idle_days`, `project_count`, `size_bytes`. |
| `suggestion` | Only with `--target-gb`: `target_bytes`, `category_ids` (in the order to clean), `total_bytes`, `reaches_target`. Absent otherwise. |

Scan status:

| Status | Tell the user |
| --- | --- |
| `ok` | Can be cleaned. |
| `empty` | Nothing to clean. |
| `not_found` | The app or tool is not installed. |
| `skipped_running` | The app is open. Close it and scan again to include it. |
| `skipped_needs_admin` | Would need administrator rights, which this skill never uses. |
| `skipped_no_permission` | The system denied access to a folder that exists. On macOS, `browser-safari` needs Full Disk Access for the terminal app; this is optional and the user's choice. |
| `unavailable` | The tool is installed but not usable now (for example, Docker is not running), or it keeps its cache in a non-standard location, which this skill never touches. The user can clean that with the tool's own command. |

Clean output: `disk_before.free_bytes`, `disk_after.free_bytes`, `freed_total_bytes`,
`results[]` (`id`, `label`, `freed_bytes`, `status`, `error_code`), `log_file_written`,
`log_location_hint`. `freed_bytes` is measured, not estimated.

Result `status` and `error_code` (the same on both platforms):

| Status | `error_code` | Tell the user |
| --- | --- | --- |
| `cleaned` | `null` | Done. |
| `partial` | `SOME_ITEMS_REMAIN` | Some items were in use or protected and stayed. |
| `skipped_running` | `APP_RUNNING` | The app was opened after the scan. Close it and scan again. |
| `skipped_no_permission` | `PERMISSION_DENIED` | The system denied the deletion. Nothing was removed. |
| `not_found` | `NOT_FOUND` | Nothing was left to clean, or the tool is gone. |
| `unavailable` | `TOOL_UNAVAILABLE` | The tool could not be used (for example, Docker stopped). |
| `unavailable` | `CUSTOM_LOCATION` | The tool's cache is in a non-standard location. Nothing was run or deleted. |
| `failed` | `TOOL_FAILED` | The tool's own clean command reported an error. |
| `failed` | `GUARD_REFUSED` | The safety check refused the location. Nothing was removed; do not work around it. |
| `failed` | `INTERNAL` | Unexpected problem. Scan again once; if it repeats, stop. |

Review output:

| Field | Meaning |
| --- | --- |
| `token`, `token_expires_in_seconds` | Pass the token to `review-apply`. Expires after 3600 seconds. |
| `groups[]` | `large-files` and `old-downloads`, each with `label`, `item_count`, `size_bytes`. |
| `total_item_count`, `total_size_bytes` | Everything listed in the page. |
| `truncated` | `true` when more than 500 items existed; the page shows the largest 500. |
| `report_opened` | `false` when the browser could not be started. Not an error (rule 15). |
| `report_location_hint` | Where the page is, as a fixed text for the user. Never open it. |
| `selection_file_hint` | Where the browser saves the selection, as a fixed text for the user. |
| `skipped_no_permission` | Present and `true` when a folder could not be read. |

Review-apply output: `selected_count`, `trashed_count`, `trashed_bytes`, `skipped_changed_count`,
`skipped_no_permission_count`, `failed_count`, `ignored_count`, `disk_before.free_bytes`,
`disk_after.free_bytes`, `space_freed_when_trash_emptied`. Nothing is ever deleted permanently by
`review-apply`; a file that cannot be moved to the Trash stays where it is.

Error output (non-zero exit): `{"schema_version":1,"error":{"code":"...","message":"..."}}`

| Code | What to do |
| --- | --- |
| `USAGE`, `INVALID_ARGUMENT` | Fix the command to match the syntax above (`--target-gb` takes 1 to 10000, `--min-size-mb` at least 10, `--downloads-age-days` at least 7). |
| `UNKNOWN_CATEGORY` | Use only ids returned by the scan. |
| `TOKEN_MISSING`, `TOKEN_INVALID`, `TOKEN_EXPIRED` | From `clean`: run `scan` again, show the new numbers, and re-confirm before cleaning. From `review-apply`: the review is older than 60 minutes or was already applied; nothing was moved. Offer to run `review` again; the user then ticks and saves again in the new page. |
| `SELECTION_NOT_FOUND` | No saved selection for this review is in the Downloads folder or on the Desktop. The user has not pressed "Done choosing" yet, or the browser saved the file somewhere else. Ask them to press "Done choosing" again and, if the browser asks where to save, to choose Downloads; then run `review-apply` again. Nothing was moved. |
| `SELECTION_INVALID` | A selection file is there but it was not saved by the page of this review (for example, saved from an older page), or the review's own files were changed. Ask the user to press "Done choosing" in the page that is open now, then run `review-apply` again. If it fails again, offer a new `review`. Never repair or write the file yourself (rule 13). Nothing was moved. |
| `CATEGORY_NOT_IN_SCAN` | The category was not `ok` in that scan. Scan again or drop it. |
| `TRASH_FLAG_REQUIRED` | `trash` needs `--empty-trash`. Add it only with the user's explicit consent. |
| `DEEP_SCAN_REQUIRED` | `node-modules-stale` needs a token from `scan --deep`. |
| `UNSUPPORTED_PLATFORM` | Only macOS and Windows are supported. Stop. |
| `INTERNAL` | Relay the message. Retry the scan once; if it fails again, stop. |
