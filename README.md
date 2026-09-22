<h1 align="center">Context Engine</h1>

<p align="center">
  <em>The project remembers. You stop re-explaining it.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/hooks-4-111111?style=flat-square" alt="4 hooks">
  <img src="https://img.shields.io/badge/setup-one%20command-111111?style=flat-square" alt="One command">
  <img src="https://img.shields.io/badge/claude%20code-v2.1.191%2B-111111?style=flat-square" alt="Claude Code v2.1.191+">
  <img src="https://img.shields.io/badge/deps-python3%20%2B%20git-111111?style=flat-square" alt="Python 3 and Git">
  <img src="https://img.shields.io/badge/license-MIT-111111?style=flat-square" alt="MIT license">
</p>

---

## The problem

You open a repo you last touched three weeks ago. Claude knows nothing about it.

So you either spend ten minutes re-explaining, or it spends them re-reading files. `claude --resume`
replays the old session instead — the whole conversation, every tool result, at full price.

None of that is state. It is the transcript of how you arrived at the state.

## What it does

Every session writes one short note: what changed, why, what was tried and rejected, what is left
open. At the next session start the last 5 commits and the earlier notes are **listed by title,
never loaded** — so the archive costs a few lines, and Claude opens the one note it needs.

```
  session start ──→  last 5 commits + earlier notes listed by title
        │
        ├──→  you work; Claude writes this session's note as it goes
        │
   /compact ──→  full transcript copied to backups/ first
        │
    /clear ──→  chat context dropped, notes listed again
        │       ← this is the reset button
        │
  session end ──→  one row in SESSION_LOG.md
```

There is no rolling memo. A memo drifts — it reads as current long after it stopped being true, and
you pay for it at every session start. A note is written once and read on demand.

---

## Install

```
/plugin marketplace add QDHShamiro/Context-Engine
/plugin install context-engine@context-engine
```

Restart Claude Code. **That is the whole setup** — it applies to every project on the machine, with
nothing to install per repo.

<details>
<summary><b>Without the plugin system</b></summary>

```bash
git clone https://github.com/QDHShamiro/Context-Engine.git
cd Context-Engine
bash install.sh
```

Registers the same four hooks directly in `~/.claude/settings.json` and appends the note rules to
`~/.claude/CLAUDE.md` instead of shipping them as a skill.

**Use one or the other, not both** — they register the same hooks and you would get each of them
twice. `install.sh` refuses to run when it sees the plugin enabled.

What it does:

1. Copies `hooks/*.sh` to `~/.claude/hooks/context-memory/`.
2. Works out the command line to register. On Windows the hook runs through `cmd.exe`, which cannot
   execute a `.sh`, so the command becomes `"<abs path to bash.exe>" "<abs path to script>"`.
3. Backs up `~/.claude/settings.json`, then **merges** its four entries in. Any hook group whose
   command does not contain `context-memory` is left untouched — existing hooks survive.
4. Appends the session-note block to `~/.claude/CLAUDE.md`, between HTML markers.
5. Adds `.claude/memory/` to git's global excludes.

Re-running replaces only its own entries. `CLAUDE_CONFIG_DIR` is honoured throughout.
</details>

**Requirements:** Claude Code v2.1.191+ and Python 3. On Windows, the Git Bash that ships with
Git for Windows. Git itself is optional — a plain directory works the same, it just has no commit
log to inject.

**Ships with:** four hooks and the `project-memory` skill that holds the rules for writing a note.

---

## The four hooks

| | Fires on | What it does |
|---|---|---|
| **inject** | `SessionStart` — `startup\|clear\|compact\|resume` | Prints the last 5 commits and an index of earlier session notes. `SessionStart` stdout goes straight into Claude's context. |
| **backup** | `PreCompact` — `manual\|auto` | Copies the full transcript to `backups/` before compaction discards it. Keeps the newest 5. |
| **log** | `SessionEnd` — all | One row per session: time, project, id, why it ended. |
| **enforce** | `Stop` | Once per session, if the project changed but this session wrote no note, blocks and asks. |

The `Stop` hook only fires when the project actually moved — a dirty tree or a new `HEAD` in a
repo, a file written since the session began anywhere else. Changes under `.claude/memory` itself
never count, so the hook's own files can't trigger it. A read-only question never triggers it. Opt out per project with `touch .claude/memory/.no-nag`.

---

## The session note

`.claude/memory/sessions/Session_Context_<title>_<id>.md` — one per session, maintained by Claude.

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

| Rule | Because |
|---|---|
| **What** and **why**, never *how* | The code already says how |
| No code, diffs, or logs | Git has the changelog, and the last 5 commits are injected beside the list |
| Only what a future session would act on | Narration is noise the next reader has to skip |

Each note is named after its session's title and follows a rename; the short id keeps it findable.

---

## Using it well

**`/clear` is the reset button.** It drops the chat context; the hook lists the notes again. You
carry on in the same terminal with the state and none of the accumulation. Nothing is lost — the
transcript stays under `~/.claude/projects/`, and `claude --resume` still reaches it.

**Write the note when the work lands.** A note assembled from memory in the last two minutes of a
session is the one that gets the reasons wrong, and the reasons are the only part worth keeping.

**`SESSION_LOG.md` finds the session you want back.** It maps a timestamp to a session id;
`claude --resume <id>` does the rest.

**`backups/` recovers what compaction dropped.** After a `/compact` the exact commands and outputs
are gone from context but still sitting in the newest backup. It is JSONL — grep it.

---

## Configuration

No config file. Three switches:

| | |
|---|---|
| `touch .claude/memory/.no-nag` | Stop the note check from blocking in this project |
| `touch .claude/memory/.debug` | Append every raw hook payload to `hook-input.log` |
| `CE_KEEP_BACKUPS` | Backups to keep. Default 5. Set it in `settings.json` under `env` |

<details>
<summary><b>Files it creates, and how to remove it</b></summary>

Per project, in `<project>/.claude/memory/`:

| | |
|---|---|
| `sessions/Session_Context_<title>_<id>.md` | One note per session. Listed at start, read on demand. Commit them. |
| `SESSION_LOG.md` | One row per session. |
| `backups/` | Pre-compaction transcripts, newest 5. |
| `.session` | Session stamp (id + HEAD) for the `Stop` check. |

**Uninstall (plugin):**

```
/plugin uninstall context-engine@context-engine
```

**Uninstall (`install.sh`):** it also touches `~/.claude/hooks/context-memory/`, four entries in
`settings.json`, a block in `CLAUDE.md`, and the memory entries in the global
gitignore.

```bash
rm -rf ~/.claude/hooks/context-memory
```

Then drop the four hook groups containing `context-memory` from `~/.claude/settings.json`, and the
`<!-- BEGIN context-memory -->` block from `~/.claude/CLAUDE.md`.

Either way, `.claude/memory/` in each project is inert once the hooks are gone — delete it or keep
it.
</details>

---

## Troubleshooting

Hooks fail silently on purpose — `PreCompact` always exits 0, because exit 2 there blocks
compaction and costs you the session. So work down this list rather than waiting for an error.

**1. Are they running?** `ls .claude/memory/` — `SESSION_LOG.md` appears after your first completed
session. If it never does, Claude Code was not restarted, or the entries are missing:

```bash
python -c "import json,io;h=json.load(io.open('$HOME/.claude/settings.json',encoding='utf-8'))['hooks'];\
[print(e,g.get('matcher','-'),x['command'][:60]) for e,gs in h.items() for g in gs for x in g['hooks'] if 'context-memory' in x['command']]"
```

**2. Is the payload arriving?** `touch .claude/memory/.debug`, start a session, read
`hook-input.log`. Empty means the hook is not being invoked — check the `bash.exe` path in the
command. Full means the script is the problem.

**3. Run one by hand.** Everything they need arrives on stdin:

```bash
echo '{"cwd":"/path/to/repo","session_id":"x","source":"startup"}' \
  | bash ~/.claude/hooks/context-memory/session-start-context.sh
```

On Windows, JSON must escape backslashes (`C:\\Users\\...`). A hand-written `"C:\Users\..."` is
invalid JSON and every field silently comes back empty — generate fixtures with
`python -c "import json;print(json.dumps({...}))"`.

**4. The Stop hook keeps interrupting.** `touch .claude/memory/.no-nag`.

**5. A hook times out.** Raise `timeout` on that entry. Windows process startup under load is the
usual cause, not the script.

---

<details>
<summary><b>Implementation notes — the traps this works around</b></summary>

- **The docs and the binary disagree.** v2.1.245 sends `source` / `trigger` / `reason` where the
  published schema says `session_start_reason` / `compaction_trigger` / `session_end_reason`. Both
  spellings are read.
- **`python3` on Windows is usually the Microsoft Store stub** — it resolves on `PATH`, then exits
  49 without running. Interpreters are probed by execution, never by lookup.
- **One Python spawn per hook.** All fields parse in a single call. `SessionEnd` runs on a 1.5s
  shared budget, and four spawns made it fail silently on roughly half of runs.
- **`stop-memo-check.sh` spawns none at all** — it runs after every turn, so it is two git calls.
- **Windows paths.** `transcript_path` arrives as `C:\Users\...`; anything matching `[A-Za-z]:*`
  goes through `cygpath -u`. A bracket pattern like `[\\/]` is not used — it loses a level to
  escaping and then matches nothing.
- **`$0` normalisation.** Each script converts its own `$0` before `dirname`, which on a backslash
  path returns `.` and fails the `_lib.sh` source — silently, because hooks swallow stderr.
- **Transcripts are read from the tail.** They reach 50 MB, and the largest context is in the last
  record anyway.
- **`*.sh` is pinned to LF** in `.gitattributes`. CRLF breaks the scripts on checkout.

`HOW-TO-SETUP.md` is the long version, written for Claude Code rather than for a human.
</details>

<details>
<summary><b>Verification status — what is proven, and what is not</b></summary>

| | |
|---|---|
| `SessionStart` injection | Verified end-to-end — a real headless session repeated the newest commit subject and a planted note title |
| `SessionEnd` logging | Verified end-to-end; real payload captured, row written with the correct reason |
| `Stop` note check | Every decision branch covered by `tests/smoke.sh`; confirmed it does not displace an existing `Stop` hook |
| Session-note naming | All three cases: a retitle renames, an unreadable transcript leaves the name alone, a session with no note creates nothing |
| Backup retention | 8 stale + 1 new → newest 5 kept; `CE_KEEP_BACKUPS=2` honoured |
| Fresh clone | LF endings intact, `bash -n` clean on every script |
| `PreCompact` backup | Verified through the exact registered command line with realistic Windows-escaped payloads, both field spellings, and malformed input. **A real interactive `/compact` has not been observed** — headless `-p` mode does not compact, so that last link is untested. |

</details>

---

<p align="center">
  <sub>MIT · Built for <a href="https://claude.com/claude-code">Claude Code</a></sub>
</p>
