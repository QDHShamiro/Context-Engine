---
description: Show what the project memo saves, and bring the memo up to date
allowed-tools: Bash(bash:*), Read, Write, Edit
---

!`bash "${CLAUDE_PLUGIN_ROOT}/hooks/memory-stats.sh" $ARGUMENTS`

Show that output verbatim. The numbers come from the transcripts' own usage
records - do not recompute, round, or embellish them.

Then bring `.claude/memory/PROJECT_CONTEXT.md` in the current project up to date
with this session, without being asked again:

- Missing? Create it, following the `project-memory` skill.
- Present? Add what this session changed, delete entries that stopped being
  true rather than correcting them underneath, and refresh the Updated date.
- One line per entry, what and why, never how. Under ~60 lines total. No code,
  logs, or diffs.

Finish with a single line saying what you added or removed, or that the memo was
already current. The size shown above was measured before this update.
