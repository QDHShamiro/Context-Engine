# Context Engine

Three Claude Code hooks that carry project state across sessions, for every project on the
machine. Claude Code already stores full JSONL transcripts under `~/.claude/projects/`, but
those are raw and expensive to re-read. This keeps one short Markdown memo per project and
injects it at session start instead.

| Hook | Event | What it does |
|---|---|---|
| `session-start-context.sh` | `SessionStart` (`startup\|resume\|compact`) | Prints `.claude/memory/PROJECT_CONTEXT.md` and the last 5 commits to stdout — `SessionStart` stdout goes straight into Claude's context. |
| `pre-compact-backup.sh` | `PreCompact` (`manual\|auto`) | Copies the full transcript to `.claude/memory/backups/<timestamp>-<trigger>.jsonl` before compaction discards it. |
| `session-end-log.sh` | `SessionEnd` (`*`) | Appends one row (time, project, session id, reason) to `.claude/memory/SESSION_LOG.md`. |

Everything lands in `<project>/.claude/memory/`, which the installer adds to git's global
excludes — it is local working state, not something to commit.

## Install

```bash
bash install.sh
```

It copies the scripts to `~/.claude/hooks/context-memory/`, merges the three hook entries into
`~/.claude/settings.json` (existing hooks are left alone; a `.bak` is written), appends the
memory instruction block to `~/.claude/CLAUDE.md`, and adds `.claude/memory/` to the global
gitignore. Re-running replaces only its own entries. Respects `CLAUDE_CONFIG_DIR`.

Restart Claude Code afterwards.

## The memo

`.claude/memory/PROJECT_CONTEXT.md` is maintained by Claude itself — the block `install.sh`
adds to `CLAUDE.md` tells it to update the file after each finished feature, fix, or decision,
one line per entry, under ~60 lines total. Nothing to run.

## Notes

- Requires Python 3 and Git. `python3` is probed by execution, not by `PATH` lookup, because on
  Windows it is usually the Microsoft Store stub that resolves but refuses to run.
- The shipping binary (v2.1.245) sends `source` / `trigger` / `reason` where the docs say
  `session_start_reason` / `compaction_trigger` / `session_end_reason`. Both spellings are read.
- Hooks fail silently by design; `PreCompact` in particular always exits 0, since exit 2 would
  block compaction. To see what a hook actually received, `touch .claude/memory/.debug` and the
  raw payloads get appended to `.claude/memory/hook-input.log`.
