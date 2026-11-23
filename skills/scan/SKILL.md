---
name: scan
description: Frees disk space on macOS and Windows. Scans caches, temp files, old logs, browser caches and developer tool caches through one bundled script that returns only totals, never file names, shows a table, then cleans only what the user chooses. Use when the user says their disk or storage is full or almost full, or asks to free up space, clean junk or temp files, clear caches, or remove old node_modules. Also triggers on Indonesian requests such as "laptop penuh", "disk penuh", "penyimpanan hampir penuh", "bersihkan sampah", "kosongkan ruang".
---

Mode for this invocation: `scan`, the default. If you loaded this skill because of a plain-language
request and not because the user typed the command, take the mode from the user's own words, as the
core instructions describe.

Read the core instructions in `${CLAUDE_PLUGIN_ROOT}/SKILL.md` now and follow them exactly, hard rules
included, in that mode. This file only selects the mode: it adds no permissions and approves nothing.
The scripts are in `${CLAUDE_PLUGIN_ROOT}/scripts/`; that plugin root is the skill directory the core
instructions refer to.

If the paths above still show a placeholder instead of a real folder, this file was not loaded as a
Claude Code plugin. Use the installed `disk-cleanup` skill instead, or say that it is not available
and stop.

Anything else the user typed with the command (may be empty): $ARGUMENTS
