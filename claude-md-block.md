<!-- BEGIN context-memory -->
## Project memory

A project keeps its history in `.claude/memory/sessions/`, one note per session:
`Session_Context_<title>_<id>.md`. There is **no rolling memo** — no `PROJECT_CONTEXT.md`, no
`<project>_Context.md`. Never create or update one.

Session start names this session's note file and lists the last few earlier notes by title. None is
loaded in full; open one when you need it. Write your own note as you go: what changed, why, what
was tried and rejected, what is left open. What and why, never how. No code, diffs, or logs.

Before redoing something that might already have been tried, open the matching earlier note.

A `Stop` hook checks once per session: if the project changed and this session has no note, it
blocks and asks. Do not wait for that. Full rules: the `project-memory` skill.
<!-- END context-memory -->
