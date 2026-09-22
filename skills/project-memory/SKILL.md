---
name: project-memory
description: >
  How to write a project's per-session notes under .claude/memory/sessions/. Load this before
  creating or updating a session note. Use when a feature lands, a bug is fixed, an architecture or
  tooling decision is made, when the Stop hook asks for a session note, or when the user says
  "session notes", "update the project memory", or asks what an earlier session decided.
---

# Project memory

A project keeps its history in `.claude/memory/sessions/`, one note per session. There is **no
rolling memo**: no `PROJECT_CONTEXT.md`, no `<project>_Context.md`. Never create or update one.

The session-start injection names this session's note file and lists the last few earlier notes by
name and title. None of them is injected in full; open one when you need it.

## `sessions/Session_Context_<title>_<id>.md`

One file per session, named after the session's own title. Rename the session and the file follows
at the next session start or end; the short session id in the name keeps it findable. Write it as
you go, not from memory at the end.

```markdown
# <one-line summary of what this session was about>
Session: <id>   Date: <YYYY-MM-DD>

## Done
- <what changed, and where>

## Why
- <the reasoning behind each decision>

## Tried and rejected
- <approach> — <why it failed>

## Left open
- <what the next session should pick up>
```

- Say **what** and **why**, never **how** — the code already says how.
- No code, diffs, or logs.
- Only worth writing if a future session would act differently for having read it. Skip narration.

## Reading earlier notes

Before redoing something that might already have been tried, or when asked what an earlier session
decided, open the matching note from `.claude/memory/sessions/` — listed under `## Earlier
sessions`, or `ls -t` that folder for older ones.

A `Stop` hook checks once per session: if the project changed and this session has no note, it
blocks and asks. Do not wait for that.
