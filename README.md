# Context Engine

Four Claude Code hooks that carry project state between sessions, for every project on the
machine.

Claude Code already stores full JSONL transcripts under `~/.claude/projects/` and can `/resume`
them, but those are raw and expensive to re-read. This keeps one short Markdown memo per project
and injects it at session start instead — same continuity, a fraction of the tokens.

## Install

```bash
git clone https://github.com/QDHShamiro/Context-Engine.git
cd Context-Engine
bash install.sh
```

Then restart Claude Code. That is the whole setup — the hooks are registered at user level, so
they apply to **every project**, with nothing to install per repo.

`install.sh` copies the scripts to `~/.claude/hooks/context-memory/`, merges its four entries
into `~/.claude/settings.json` (existing hooks are left alone, a `.bak` is written), appends the
memo-maintenance instruction to `~/.claude/CLAUDE.md`, and adds `.claude/memory/` to git's global
excludes. Re-running replaces only its own entries. Honours `CLAUDE_CONFIG_DIR`.

Requires Python 3 and Git.

## What runs, and when

| Hook | Event | Effect |
|---|---|---|
| `session-start-context.sh` | `SessionStart` — `startup\|resume\|compact` | Prints `PROJECT_CONTEXT.md` and the last 5 commits to stdout. `SessionStart` stdout is added to Claude's context, so this is what Claude sees before your first message. Also stamps `.session` for the Stop check. |
| `pre-compact-backup.sh` | `PreCompact` — `manual\|auto` | Copies the full transcript to `backups/<timestamp>-<trigger>.jsonl` before compaction throws it away. Keeps the newest 5. |
| `session-end-log.sh` | `SessionEnd` — all | Appends one row (time, project, session id, reason) to `SESSION_LOG.md`. |
| `stop-memo-check.sh` | `Stop` | Once per session: if the repo changed but the memo did not, blocks and asks Claude to update it. |

Everything lives in `<project>/.claude/memory/`:

```
PROJECT_CONTEXT.md   the memo — the only file you'd ever edit by hand
SESSION_LOG.md       one row per session
backups/             pre-compaction transcripts, newest 5
.session             session stamp (id + HEAD), written at session start
```

## Using it well

**Let Claude write the memo.** The block `install.sh` adds to `~/.claude/CLAUDE.md` tells it to
update `PROJECT_CONTEXT.md` after each finished feature, fix, or decision. You should not have to
ask. If it drifts in a long session, "update the project memory" is enough — and the `Stop` hook
catches the case where a session changed the repo and recorded nothing.

**Keep it short.** This file is injected into context at every single session start, so every
line you add is a line you pay for forever. Under ~60 lines. One line per entry. Say *what* and
*why*; never *how* — the code already says how, and the memo goes stale the moment it tries to
describe implementation.

**What belongs in it:** decisions and their reasons, what currently works, what is deliberately
deferred, and the blocker you'd otherwise have to rediscover. **What does not:** code, diffs,
logs, file listings, or a changelog. Git already has the changelog, and the last five commits are
injected next to the memo anyway.

**Delete, don't append.** When an entry stops being true, remove it. A memo that accumulates
corrections under stale lines is worse than no memo, because it reads as current.

**Seed existing projects by hand.** A repo you have worked in for months starts with an empty
memo — the first session there only gets the commit log. Write four lines yourself and let Claude
maintain it from there:

```bash
mkdir -p .claude/memory && cat > .claude/memory/PROJECT_CONTEXT.md <<'EOF'
# myproject — Context
Updated: 2026-08-25

## What this is
One or two lines.

## State
- <what works now>

## Decisions
- <decision> — <why, one clause>

## Open
- <next thing, blocker, or deferred item>
EOF
```

**`SESSION_LOG.md` is for finding the session you want back.** It maps timestamps to session ids;
`claude --resume <id>` takes it from there.

**`backups/` is for recovering detail compaction dropped.** After a `/compact`, the exact commands
and outputs are gone from context but still in the newest backup file. Grep it.

## Configuration

There is no config file. Three switches, all inside a project's `.claude/memory/`:

| | |
|---|---|
| `touch .claude/memory/.no-nag` | Stop the memo check from blocking in this project. |
| `touch .claude/memory/.debug` | Append every raw hook payload to `hook-input.log`. Delete the file to stop. |
| `CE_KEEP_BACKUPS=20` | Number of pre-compaction backups to keep. Default 5. Set in the hook's environment. |

To remove everything: delete the four `context-memory` entries from `~/.claude/settings.json`,
delete `~/.claude/hooks/context-memory/`, and remove the `<!-- BEGIN context-memory -->` block
from `~/.claude/CLAUDE.md`.

## Troubleshooting

Hooks fail silently on purpose — `PreCompact` in particular always exits 0, because exit 2 would
block compaction and cost you the session.

1. `ls .claude/memory/` — if `SESSION_LOG.md` never appears, the hooks are not running at all.
   Check that Claude Code was restarted after installing.
2. `touch .claude/memory/.debug`, start a session, then read `hook-input.log`. If it stays empty
   the hook is not being invoked; if it fills up, the payload is there and the script is the
   problem.
3. Run a hook by hand against a real payload — everything they need arrives on stdin:
   ```bash
   echo '{"cwd":"/path/to/repo","session_id":"x","source":"startup"}' \
     | bash ~/.claude/hooks/context-memory/session-start-context.sh
   ```

## Implementation notes

- The shipping binary (v2.1.245) sends `source` / `trigger` / `reason` where the documentation
  says `session_start_reason` / `compaction_trigger` / `session_end_reason`. Both spellings are
  read, so this works either way.
- Interpreters are probed by execution rather than `PATH` lookup: on Windows `python3` is usually
  the Microsoft Store stub, which resolves happily and then refuses to run.
- All hook fields are parsed in a single Python spawn. `SessionEnd` runs on a short budget and on
  Windows process startup is the expensive part.
- `stop-memo-check.sh` reads no stdin and spawns no Python — it runs at the end of every assistant
  turn, so it is kept to a couple of git calls.
- `*.sh` is pinned to LF in `.gitattributes`; CRLF would break the scripts on checkout.
