---
name: disk-cleanup
description: Frees disk space on macOS and Windows by clearing caches, temp files, old logs, browser caches and developer tool caches through one bundled script that returns only aggregated sizes, so no file names or personal data are ever shown to the AI. Use when the user says their disk or storage is full or almost full, the laptop is out of space, or asks to free up space, clean junk or temp files, clear caches, or remove old node_modules. Also triggers on Indonesian requests such as "laptop penuh", "disk penuh", "penyimpanan hampir penuh", "bersihkan sampah", "kosongkan ruang".
license: MIT
compatibility: macOS (bash 3.2+) or Windows (Windows PowerShell 5.1+). Needs permission to run a local script. No network access, no sudo or admin rights.
metadata:
  author: awankkaley
  version: "1.0.0"
---

# Disk cleanup

You free disk space by running ONE bundled script. It measures and deletes on its own and gives you
only aggregated JSON (category, size, count, status). You never see file names or paths, and you must
not go looking for them. This is the whole point of the skill: the user's files stay private.

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
8. If the user wants something outside the category list (large files, duplicates, Downloads,
   Documents, photos, old installers, uninstalling apps), decline that part. Explain that finding those
   would require reading their file names, which this skill never does, and that they can review those
   folders themselves.
9. Do not quit, kill, or restart the user's apps. If a category is skipped because its app is running,
   ask the user to close the app, then scan again.
10. Reply in the user's language. Category `label` and `impact` texts are English; translate them.
11. If the script prints an error JSON, relay its `message` to the user and do what it says. Do not
    work around it.

## How to run

`<skill-dir>` is the directory that contains this SKILL.md. Use its absolute path and keep the quotes.
If your harness expanded this placeholder into a real path, that is the skill directory:
`${CLAUDE_SKILL_DIR}` (ignore this line if it still shows a placeholder).

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
scan  [--deep] [--min-age-days N] [--projects-dir PATH]
clean --token ID --categories id1,id2 [--empty-trash] [--min-idle-days N] [--log]
--help | --version
```

stdout is always exactly one JSON document. On Linux or any other system the script returns
`UNSUPPORTED_PLATFORM`; tell the user the skill only supports macOS and Windows.

## Workflow

### 1. Scan

Run `scan`. It deletes nothing. Keep the `token`; it is valid for 15 minutes and for one `clean` only.
Never run `scan` and `clean` in the same turn: the user has to see the scan result first.

### 2. Report

Show one table of the categories with status `ok`, sorted by `size_bytes` descending, with columns:
label, size (human-readable, e.g. 1.2 GB), risk, impact, status. Then:

- State the recommended total (`recommended_total_bytes`) and the current free space (`disk`).
- Briefly list skipped categories and why (see the status table below). Leave out `empty` and
  `not_found` unless the user asks.
- A `null` size means the size cannot be known in advance; say "unknown", not zero. `pnpm-store` is
  always like this: only packages no project references are removed, so the amount is known after
  cleaning. Such categories add nothing to `recommended_total_bytes`.

### 3. Ask

Ask which categories to clean. Suggest the ones with `recommended: true` as the default. Mention
separately, and never pre-select:

- anything with risk `rebuild_needed` or `irreversible`;
- `trash`: emptying it is permanent. Include it only if the user explicitly agrees, and then also pass
  `--empty-trash`.

Wait for the answer. "Yes" or "go ahead" means the recommended set only.

### 4. Clean

```
clean --token <token> --categories <approved ids, comma-separated>
```

Deletion is permanent; nothing is moved to the Trash or Recycle Bin.

### 5. Report the result

State `freed_total_bytes`, free space before and after (`disk_before`, `disk_after`), and one line per
result that is not `cleaned` explaining its status. If `freed_total_bytes` is small compared with the
scan, say so plainly; do not overstate.

### Deep scan (stale node_modules)

Run `scan --deep` only when the user asks about `node_modules` or old projects, or after you offered it
and they agreed. Tell them first that it walks their home folder read-only and can take a few minutes.
If they name a projects folder, pass it with `--projects-dir`.

The `node-modules-stale` category has `buckets` by idle time (30-90, 90-180, 180+ days) with project
counts and sizes. Present the buckets and let the user choose the threshold. Then clean with
`--categories node-modules-stale --min-idle-days N` (default 30, minimum 30). Explain that the affected
projects need `npm install` (or yarn, pnpm, bun) before they run again. Project names are never
available to you; do not try to find them.

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
| `categories[].size_bytes`, `.item_count` | Reclaimable bytes and file count. May be `null`. |
| `categories[].status` | See below. Only `ok` can be cleaned. |
| `categories[].recommended` | `true` only for risk `safe`. |
| `categories[].risk` | `safe`, `rebuild_needed`, `irreversible`. |
| `categories[].requires_flag` | `"--empty-trash"` for `trash`, otherwise `null`. |
| `categories[].buckets[]` | Only `node-modules-stale`: `id`, `min_idle_days`, `project_count`, `size_bytes`. |

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

Error output (non-zero exit): `{"schema_version":1,"error":{"code":"...","message":"..."}}`

| Code | What to do |
| --- | --- |
| `USAGE`, `INVALID_ARGUMENT` | Fix the command to match the syntax above. |
| `UNKNOWN_CATEGORY` | Use only ids returned by the scan. |
| `TOKEN_MISSING`, `TOKEN_INVALID`, `TOKEN_EXPIRED` | Run `scan` again, show the new numbers, and re-confirm before cleaning. |
| `CATEGORY_NOT_IN_SCAN` | The category was not `ok` in that scan. Scan again or drop it. |
| `TRASH_FLAG_REQUIRED` | `trash` needs `--empty-trash`. Add it only with the user's explicit consent. |
| `DEEP_SCAN_REQUIRED` | `node-modules-stale` needs a token from `scan --deep`. |
| `UNSUPPORTED_PLATFORM` | Only macOS and Windows are supported. Stop. |
| `INTERNAL` | Relay the message. Retry the scan once; if it fails again, stop. |
