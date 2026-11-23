---
name: review
description: Review your own large files and old downloads. Opens a private page in your browser that only you can see, where you tick what you no longer need; the ticked files are then moved to the Trash or Recycle Bin. The AI only ever gets counts and totals.
disable-model-invocation: true
---

Mode for this invocation: `review`.

Read the core instructions in `${CLAUDE_PLUGIN_ROOT}/SKILL.md` now and follow them exactly, hard rules
included, in that mode. This file only selects the mode: it adds no permissions and approves nothing.
The scripts are in `${CLAUDE_PLUGIN_ROOT}/scripts/`; that plugin root is the skill directory the core
instructions refer to.

If the paths above still show a placeholder instead of a real folder, this file was not loaded as a
Claude Code plugin. Use the installed `disk-cleanup` skill instead, or say that it is not available
and stop.

Anything else the user typed with the command (may be empty): $ARGUMENTS
