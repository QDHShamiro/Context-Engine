<!-- BEGIN context-memory -->
## Project memory — `.claude/memory/PROJECT_CONTEXT.md`

Every project keeps a short living memo at `.claude/memory/PROJECT_CONTEXT.md` in the repo
root. A SessionStart hook injects it automatically, so it is the only thing that carries state
across sessions. Nobody prompts you to update it — keep it accurate yourself.

Update it in the same turn as the work, whenever:
- a feature is finished
- a bug is fixed
- an architecture, library, or tooling decision is made
- a plan changes, or something is deliberately deferred

Create the file if missing, using this shape:

```markdown
# <project> — Context
Updated: <YYYY-MM-DD>

## What this is
One or two lines.

## State
- <what works now>

## Decisions
- <decision> — <why, one clause>

## Open
- <next thing, blocker, or deferred item>
```

Rules:
- **Write it in English**, whatever language the conversation is in. This file is re-read at every
  session start forever; English tokenises tighter and the models read it better, so the same
  meaning costs fewer tokens and survives the round trip more accurately.
- One line per entry. Say **what** and **why**, never how — the code already says how.
- Delete entries that stopped being true. Never append a correction under a stale line.
- Whole file stays under ~60 lines. Past that, compress the oldest `Decisions` into one line.
- No code, logs, diffs, or file dumps. It is a memo, not a changelog; git has the changelog.

A Stop hook checks this once per session: if the repo changed and the memo did not, it blocks
and asks for the update. Do not wait for that block — writing the entry when the work lands is
the point, and a memo written at the end from memory is the one that gets details wrong.
<!-- END context-memory -->
