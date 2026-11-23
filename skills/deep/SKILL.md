---
name: deep
description: Deep scan. Also looks for node_modules folders in projects left untouched for months (macOS, Windows). Walks the home folder read-only and can take a few minutes, shows totals by idle time, then waits for your choice.
argument-hint: "[projects folder]"
disable-model-invocation: true
---

Mode for this invocation: `deep`.

Read the core instructions in `${CLAUDE_PLUGIN_ROOT}/SKILL.md` now and follow them exactly, hard rules
included, in that mode. This file only selects the mode: it adds no permissions and approves nothing.
The scripts are in `${CLAUDE_PLUGIN_ROOT}/scripts/`; that plugin root is the skill directory the core
instructions refer to.

If the paths above still show a placeholder instead of a real folder, this file was not loaded as a
Claude Code plugin. Use the installed `disk-cleanup` skill instead, or say that it is not available
and stop.

Anything else the user typed with the command (may be empty): $ARGUMENTS
