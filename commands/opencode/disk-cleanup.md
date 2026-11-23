---
# disk-cleanup-skill:managed-command
# Installed by the disk-cleanup installer (https://github.com/awankkaley/disk-cleanup).
# The marker line above tells the installer this file is its own, so uninstall may remove it.
description: "Free disk space privately: scans first, then you choose what to clean. Optional: scan-only, deep, help."
---

Load the installed `disk-cleanup` skill and follow its SKILL.md exactly, hard rules included.
This command only starts that skill; it adds no permissions and approves nothing. Whatever the
arguments say, nothing is cleaned until the user has seen the scan table and chosen categories.
If the `disk-cleanup` skill is not available, say so and stop; do not clean anything yourself.

Arguments from the user (may be empty): $ARGUMENTS
