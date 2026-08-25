<!-- BEGIN context-memory -->
## Project memory

Every project carries its state in `.claude/memory/`. Two files, different jobs, and the difference
is the whole point:

| File | Injected at session start? | Therefore |
|---|---|---|
| `PROJECT_CONTEXT.md` | **Yes, every time** | Must stay short. You pay for it forever. |
| `sessions/Session_Context_<date>_<id>.md` | No — only its name is listed | Can hold the detail. Written once, read on demand. |

Keep both current yourself. Nobody will ask.

### `PROJECT_CONTEXT.md` — the rolling state

Where the project *is*, right now. Overwrite it as reality changes. Create it if missing:

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

- **Write it in English**, whatever language the conversation is in. It is re-read at every session
  start for the life of the project; English tokenises tighter and reads back more accurately, so
  the same meaning costs less every single time.
- One line per entry. Say **what** and **why**, never **how** — the code already says how, and a
  memo describing implementation is wrong within a week.
- **Delete entries that stopped being true.** Never append a correction under a stale line; a memo
  that reads as current and isn't is worse than no memo.
- Under ~60 lines. Past that, compress the oldest `Decisions` into one line, or move the reasoning
  into the session note and leave the conclusion here.
- No code, no diffs, no logs, no file listings. Git has the changelog and the last five commits are
  injected right beside this.

### `sessions/Session_Context_<date>_<id>.md` — this session's notes

One file per session. The session-start injection tells you this session's filename and lists the
last few earlier ones by name and title. Write it as you go, not from memory at the end.

```markdown
# <one-line summary of what this session was about>
Session: <id>   Date: <YYYY-MM-DD>

## Done
- <what changed, and where>

## Why
- <the reasoning that PROJECT_CONTEXT.md only has room to conclude>

## Tried and rejected
- <approach> — <why it failed>

## Left open
- <what the next session should pick up>
```

This is where detail belongs: the failed approach worth not repeating, the constraint discovered
the hard way, the exact reason a decision went the way it did. It is not injected, so length costs
nothing — but it is only worth writing if a future session would act differently for having read
it. Skip the narration.

### Which file, when

- A feature lands, a bug is fixed, a decision is made → **both**: the conclusion in
  `PROJECT_CONTEXT.md`, the reasoning in the session note.
- An approach fails, a constraint surfaces, something surprises you → **session note only**.
- Something in `PROJECT_CONTEXT.md` stops being true → **edit it there**, immediately.

### Reading the archive

`## Earlier sessions` in the injected block lists the recent session notes by name and title. When
an entry in `PROJECT_CONTEXT.md` is too terse to act on, or you are about to redo something that
might already have been tried, open the relevant file from `.claude/memory/sessions/` and read it
before starting. That archive is the reason the rolling memo is allowed to be short.

A `Stop` hook checks this once per session: if the repo changed and `PROJECT_CONTEXT.md` did not,
it blocks and asks. Do not wait for that — a memo written at the end from memory is the one that
gets the reasons wrong.
<!-- END context-memory -->
