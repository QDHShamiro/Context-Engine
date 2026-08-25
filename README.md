<h1 align="center">Context Engine</h1>

<p align="center">
  <em>The project remembers. You stop re-explaining it.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/hooks-4-111111?style=flat-square" alt="4 hooks">
  <img src="https://img.shields.io/badge/claude%20code-v2.1.191%2B-111111?style=flat-square" alt="Claude Code v2.1.191+">
  <img src="https://img.shields.io/badge/deps-python3%20%2B%20git-111111?style=flat-square" alt="Python 3 and Git">
  <img src="https://img.shields.io/badge/license-MIT-111111?style=flat-square" alt="MIT license">
</p>

<p align="center">
  <strong>99.6% of the cold start, gone &middot; 145,261 &rarr; 590 tokens</strong><br>
  <sub>Median session-end context across 127 real sessions in 22 projects, read from the
  transcripts' own <code>usage</code> records — only the memo side is an estimate.
  Run <code>/memory-stats --all</code> to reproduce it on your own machine.</sub>
</p>

---

Four Claude Code hooks that carry project state between sessions, for every project on the
machine.

Claude Code already stores full JSONL transcripts under `~/.claude/projects/` and can replay them
with `claude --resume`. That solves *one* session continuing. It does not solve the ordinary case:
you open a repo you last touched three weeks ago and Claude knows nothing about it, so you spend
the first ten minutes re-explaining, or it spends them re-reading files. Replaying the raw
transcript is worse — it is the whole conversation, tool output included, at full token cost.

This keeps one short Markdown memo per project and injects it at session start instead. Same
continuity, a fraction of the tokens, and it maintains itself.

---

## Requirements

| | |
|---|---|
| Claude Code | v2.1.191+ (comma matchers); developed against v2.1.245 |
| Python 3 | any; used only to parse the hook payload |
| Git | used for the commit log, the project root, and the change check |
| Shell | Bash. On Windows the Git Bash that ships with Git for Windows is used, and the installer wires the hooks to it by absolute path |

---

## Install

```bash
git clone https://github.com/QDHShamiro/Context-Engine.git
cd Context-Engine
bash install.sh
```

Then **restart Claude Code**. Hooks are read at session start; a running session will not pick
them up.

That is the entire setup. The hooks are registered at user level, so they apply to **every
project**, with nothing to install per repo.

### What `install.sh` actually does

1. Copies `hooks/*.sh` to `~/.claude/hooks/context-memory/` and marks them executable.
2. Works out the command line to register. On Windows the hook is executed by `cmd.exe`, which
   cannot run a `.sh` file, so the command is `"<abs path to bash.exe>" "<abs path to script>"`
   with forward slashes. Elsewhere it is just the script path.
3. Backs up `~/.claude/settings.json` to `settings.json.bak`, then **merges** its four entries in.
   Any hook group whose command does not contain `context-memory` is left exactly as it was, so
   existing hooks survive. Re-running replaces only its own entries.
4. Appends the memo-maintenance block from `claude-md-block.md` to `~/.claude/CLAUDE.md`, between
   `<!-- BEGIN context-memory -->` and `<!-- END context-memory -->` markers. Re-running replaces
   the block instead of duplicating it.
5. Adds `.claude/memory/` to git's global excludes. If `core.excludesFile` is unset it is pointed
   at `~/.gitignore_global`; if it is already set, the line is appended to whatever file it names.

`CLAUDE_CONFIG_DIR` is honoured throughout, so you can install into an alternate config root.

---

## What runs, and when

| Hook | Event | Matcher | Timeout |
|---|---|---|---|
| `session-start-context.sh` | `SessionStart` | `startup\|clear\|compact\|resume` | 15s |
| `pre-compact-backup.sh` | `PreCompact` | `manual\|auto` | 30s |
| `session-end-log.sh` | `SessionEnd` | `*` | 10s |
| `stop-memo-check.sh` | `Stop` | none — `Stop` takes no matcher | 10s |

### `SessionStart` → inject the memo

Prints `PROJECT_CONTEXT.md` followed by the last five commits. `SessionStart` is one of the few
events whose plain stdout is added to Claude's context, so this is what Claude sees before your
first message.

If neither the memo nor a git log exists it prints **nothing** and exits 0, so a scratch directory
costs zero tokens.

It also writes `.claude/memory/.session` — two lines, the session id and the current `HEAD` — which
is what the `Stop` check compares against later. On `source=compact` the stamp is deliberately left
alone: compaction restarts the session but not the work.

Output looks like:

```
# myproject — Context
Updated: 2026-08-25

## State
- Auth rewrite landed; sessions are JWT now.

## Open
- Refresh-token rotation still unimplemented.

## Recent commits
a1b2c3d 2026-08-24 feat: JWT sessions
...

_(Injected by the SessionStart memory hook. Keep .claude/memory/PROJECT_CONTEXT.md current as you work.)_
```

### `PreCompact` → keep the transcript

Copies the full transcript to `.claude/memory/backups/<timestamp>-<trigger>.jsonl` before
compaction discards it, then deletes all but the newest five.

This hook **always exits 0**. Exit 2 on `PreCompact` blocks compaction, which would cost you the
session — so every operation is guarded and failure is silent by design.

### `SessionEnd` → log the session

Appends one row to `SESSION_LOG.md`:

```
| ended            | project   | session                              | reason |
|------------------|-----------|--------------------------------------|--------|
| 2026-08-25 19:47 | myproject | 5d204d76-3f5a-43f8-ad90-79e7f61684ae | clear  |
```

`reason` is one of `clear`, `resume`, `logout`, `prompt_input_exit`, `other`. The session id is
what `claude --resume <id>` takes.

### `Stop` → enforce the memo

Runs at the end of every assistant turn. Blocks **once per session** — exit 2, which feeds the
message back to Claude and makes it continue — when the repo moved but the memo did not.

It stays quiet unless all of these hold:

- the cwd is inside a git repo, and `.session` exists (so a session actually started here)
- `.claude/memory/.no-nag` does not exist
- it has not already blocked this session (a third line `nagged` is appended to `.session`)
- `PROJECT_CONTEXT.md` is not newer than `.session` — i.e. it was not touched this session
- the working tree is dirty **or** `HEAD` moved since session start

That last condition is what keeps it from nagging after a read-only question. Because it fires on
every turn, this hook reads no stdin and spawns no Python — it is two git calls and a `sed`.

---

## What it saves

`/memory-stats` does two things: it reports the saving, then brings this project's memo up to
date — creating it if there is none. So the command that tells you the memo is worth having is
also the one that writes it. `--all` adds a machine-wide summary:

```
  Context Engine

    sessions                     1   today
    memo                       810   tokens, 49 lines, updated today
    transcripts               3 MB   on disk

    picking up cold        313,834   tokens - what resuming the last session costs
    picking up by memo         810   tokens - your memo instead
                        ----------
    you save               313,024   99.7% less, 387.4x smaller

  Overall - everything on this machine

    projects                    22   2 with a memo, 20 without
    sessions                   129   2026-08-01 to today
    transcripts             364 MB   on disk under ~/.claude/projects
    biggest session        842,842   tokens
    typical session        137,701   tokens

    picking up cold        137,701   tokens - a typical session, resumed
    picking up by memo         810   tokens - a typical memo instead
                        ----------
    you save               136,891   99.4% less, 170.0x smaller

    20 projects here with sessions but no memo yet.

  ========================================================================
   OVERALL SAVED      27,841,195 tokens   over 129 sessions in 22 projects
  ========================================================================
```

The overall block prints in every mode — it is the number you came for, not something to pass a
flag for. `--all` swaps the single project at the top for a per-project breakdown.

Without a memo, the way back into a project is `claude --resume`, which reloads everything that
session was holding when it ended — the cold number. With a memo you load the memo instead. Same
starting point, that much less to pay for.

The cumulative line is the one hypothetical and is labelled as one; the lines above it are direct
measurements.

**What is being compared.** Without a memo, the way to get state back is `claude --resume`, which
costs whatever that session was holding when it ended. That figure is not estimated — every
assistant record in a transcript carries a `usage` block, and the script takes
`input_tokens + cache_read_input_tokens + cache_creation_input_tokens` from the last one. Only the
memo side is estimated, at four characters per token.

**What it does not claim.** Only the cold start changes. What you build up *during* a session is
unchanged, and the memo is a summary rather than a replacement — when you need the detail back,
that is what `.claude/memory/backups/` is for.

Run it from anywhere inside a repo — it resolves to the git root, so sessions started in a
subdirectory still count. In a project with nothing recorded yet it shows the machine-wide picture
rather than an empty result, so the figure is on screen either way.

Without the slash command:

```bash
bash ~/.claude/hooks/context-memory/memory-stats.sh          # this project
bash ~/.claude/hooks/context-memory/memory-stats.sh --all    # everything, plus summary
bash ~/.claude/hooks/context-memory/memory-stats.sh --json   # machine-readable
```

---

## Files

Per project, all inside `<project>/.claude/memory/`:

| | |
|---|---|
| `PROJECT_CONTEXT.md` | The memo. The only file you would ever edit by hand. |
| `SESSION_LOG.md` | One row per session. |
| `backups/` | Pre-compaction transcripts, newest 5. |
| `.session` | Session stamp: id, HEAD, and `nagged` once the Stop check has fired. |
| `.no-nag` | Optional. Disables the Stop check in this project. |
| `.debug` | Optional. Makes every hook append its raw payload to `hook-input.log`. |
| `hook-input.log` | Only written while `.debug` exists. |

The whole directory is local working state and is added to git's global excludes by the installer.

At user level:

| | |
|---|---|
| `~/.claude/hooks/context-memory/*.sh` | The hook scripts and `memory-stats.sh`. |
| `~/.claude/settings.json` | Four hook entries. |
| `~/.claude/commands/memory-stats.md` | The `/memory-stats` slash command. |
| `~/.claude/CLAUDE.md` | The memo-maintenance block. |
| `~/.gitignore_global` | `.claude/memory/` — unless `core.excludesFile` already pointed elsewhere. |

---

## The memo

`PROJECT_CONTEXT.md` is maintained by Claude, not by you. The block appended to `~/.claude/CLAUDE.md`
tells it to update the file after each finished feature, fix, or architecture decision. Shape:

```markdown
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
```

The rules that ship in `CLAUDE.md`:

- **Written in English**, whatever language you work in. The memo is re-read at every session start
  forever; English tokenises tighter and the models read it more accurately, so the same meaning
  costs less and survives the round trip better.
- One line per entry. Say **what** and **why**, never **how** — the code already says how, and a
  memo that describes implementation is stale the week after it is written.
- Delete entries that stopped being true. Never append a correction under a stale line.
- Under ~60 lines. Past that, compress the oldest `Decisions` into one line.
- No code, logs, diffs, or file dumps. It is a memo, not a changelog; git has the changelog, and
  the last five commits are injected right next to it anyway.

---

## Using it well

**`/clear` is the reset button.** It drops the chat context, and the `SessionStart` hook puts the
memo straight back — so you carry on in the same terminal with the state and none of the
accumulation. That is the moment the numbers below actually happen. Nothing is lost: the transcript
stays under `~/.claude/projects/`, and `claude --resume` still reaches it.

**Let Claude write it.** You should not have to ask. If it drifts in a long session, "update the
project memory" is enough, `/memory-stats` updates it on the spot, and the `Stop` check catches the
session that changed the repo and recorded nothing.

**Keep it short — this is the whole trade.** The memo is injected at *every* session start, so
every line you add is a line you pay for in every future session in that repo. A 200-line memo is
worse than no memo: you have reinvented the transcript, at transcript prices, with none of the
detail.

**Write it when the work lands, not at the end.** A memo assembled from memory in the last two
minutes of a session is the one that gets the reasons wrong, and the reasons are the only part
worth keeping.

**Seed existing repos by hand.** A project you have worked in for months starts with an empty
memo — the first session there gets only the commit log. Write four lines and let Claude take over:

```bash
mkdir -p .claude/memory && cat > .claude/memory/PROJECT_CONTEXT.md <<'EOF'
# myproject — Context
Updated: 2026-08-25

## What this is
One or two lines.

## State
- <what works now>

## Open
- <next thing or blocker>
EOF
```

**`SESSION_LOG.md` is how you find the session you want back.** It maps a timestamp to a session
id; `claude --resume <id>` does the rest. Useful when you remember *when* something happened but
not which session it was.

**`backups/` is how you recover what compaction dropped.** After a `/compact` the exact commands,
paths, and outputs are gone from context but still sitting in the newest backup file. It is JSONL —
grep it.

**Don't commit `.claude/memory/`.** The installer handles this globally. If a repo already tracked
it, `git rm -r --cached .claude/memory` once.

---

## Configuration

No config file. Three switches:

| | |
|---|---|
| `touch .claude/memory/.no-nag` | Stop the memo check from blocking in this project. |
| `touch .claude/memory/.debug` | Append every raw hook payload to `hook-input.log`. Delete to stop. |
| `CE_KEEP_BACKUPS` | Number of pre-compaction backups to keep. Default 5. |

`CE_KEEP_BACKUPS` is read from the hook's environment, so set it in `~/.claude/settings.json`:

```json
{
  "env": {
    "CE_KEEP_BACKUPS": "20"
  }
}
```

### The entries the installer writes

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|clear|compact|resume",
        "hooks": [{ "type": "command", "command": "\"C:/Program Files/Git/usr/bin/bash.exe\" \"C:/Users/you/.claude/hooks/context-memory/session-start-context.sh\"", "timeout": 15 }]
      }
    ],
    "PreCompact": [
      {
        "matcher": "manual|auto",
        "hooks": [{ "type": "command", "command": "... pre-compact-backup.sh", "timeout": 30 }]
      }
    ],
    "SessionEnd": [
      {
        "matcher": "*",
        "hooks": [{ "type": "command", "command": "... session-end-log.sh", "timeout": 10 }]
      }
    ],
    "Stop": [
      {
        "hooks": [{ "type": "command", "command": "... stop-memo-check.sh", "timeout": 10 }]
      }
    ]
  }
}
```

On Linux and macOS the `command` is just the script path, with no `bash.exe` prefix.

`fork` is the one `SessionStart` matcher left out: a forked session carries its parent's context,
so the memo would be duplicate. `resume` is included for the same reason it is arguable — the
transcript is already loaded, so the memo costs its own size for nothing there. Drop it from the
matcher if that bothers you.

---

## Uninstall

```bash
rm -rf ~/.claude/hooks/context-memory ~/.claude/commands/memory-stats.md
```

Then remove the four hook groups whose `command` contains `context-memory` from
`~/.claude/settings.json`, and delete the `<!-- BEGIN context-memory -->` … `<!-- END context-memory -->`
block from `~/.claude/CLAUDE.md`. Optionally drop `.claude/memory/` from `~/.gitignore_global`.

Per-project data in `.claude/memory/` is inert once the hooks are gone; delete it or keep it.

---

## Troubleshooting

Hooks fail silently on purpose. `PreCompact` in particular always exits 0, because exit 2 there
blocks compaction. So work down this list rather than waiting for an error.

**1. Are the hooks running at all?**

```bash
ls .claude/memory/
```

`SESSION_LOG.md` appears after your first completed session in that project. If it never shows up,
Claude Code was not restarted after install, or the entries are missing from `settings.json`:

```bash
python -c "import json,io;h=json.load(io.open('$HOME/.claude/settings.json',encoding='utf-8'))['hooks'];\
[print(e,g.get('matcher','-'),x['command'][:60]) for e,gs in h.items() for g in gs for x in g['hooks'] if 'context-memory' in x['command']]"
```

**2. Is the payload arriving?**

```bash
touch .claude/memory/.debug
# start a session, then:
cat .claude/memory/hook-input.log
```

Empty means the hook is not being invoked — check the command line in `settings.json`, especially
the path to `bash.exe`. Full means the payload is fine and the script is the problem.

**3. Run a hook by hand.** Everything they need arrives on stdin, so they are trivially testable:

```bash
echo '{"cwd":"/path/to/repo","session_id":"x","source":"startup"}' \
  | bash ~/.claude/hooks/context-memory/session-start-context.sh

echo '{"cwd":"/path/to/repo","transcript_path":"/tmp/t.jsonl","trigger":"manual"}' \
  | bash ~/.claude/hooks/context-memory/pre-compact-backup.sh
```

On Windows, JSON must escape backslashes (`C:\\Users\\...`) — a hand-written `"C:\Users\..."` is
invalid JSON and the parser will silently return empty fields. Generate fixtures with
`python -c "import json;print(json.dumps({...}))"` rather than by hand.

**4. The Stop hook keeps interrupting.** `touch .claude/memory/.no-nag`. If it fires when the repo
is clean, check that `.session` line 2 holds the real `HEAD` — a stale stamp makes every turn look
like HEAD moved.

**5. A hook times out.** Raise `timeout` on that entry in `settings.json`. Windows process startup
under load is the usual cause, not the script.

---

## Platform and implementation notes

- **The docs and the binary disagree on field names.** v2.1.245 sends `source`, `trigger`, and
  `reason`; the published schema says `session_start_reason`, `compaction_trigger`, and
  `session_end_reason`. Both spellings are read, newest first, so this keeps working either way.
- **`python3` on Windows is usually the Microsoft Store stub** — it resolves on `PATH` and then
  exits 49 without running anything. Interpreters are therefore probed by execution (`py -c ""`),
  never by `command -v` alone.
- **One Python spawn per hook.** All fields are parsed in a single call and `eval`'d into shell
  variables via `shlex.quote`. `SessionEnd` runs on a short shared budget and on Windows process
  startup dominates, so four spawns made it flaky and one does not.
- **`stop-memo-check.sh` is the exception** — no stdin, no Python. It runs after every turn, so it
  gets everything from `$PWD` and the stamp file.
- **Windows paths.** `transcript_path` and `cwd` arrive as `C:\Users\...`. Anything matching
  `[A-Za-z]:*` is passed through `cygpath -u`; a bracket pattern like `[\\/]` is not used because
  it survives escaping layers badly.
- **`$0` normalisation.** Each script converts its own `$0` before `dirname`, because `dirname` on
  a backslash path returns `.` and the `_lib.sh` source would fail.
- **`*.sh` is pinned to LF** in `.gitattributes`. CRLF breaks the scripts on checkout — Git Bash
  carries the `\r` into variable values.
- **Idempotence.** Both the `settings.json` merge and the `CLAUDE.md` block key off the string
  `context-memory` / the HTML markers, so `install.sh` can be re-run freely.

---

## Repo layout

```
hooks/
  _lib.sh                    payload parsing, path conversion, project root, debug dump
  session-start-context.sh   SessionStart
  pre-compact-backup.sh      PreCompact
  session-end-log.sh         SessionEnd
  stop-memo-check.sh         Stop
  memory-stats.sh            not a hook — backs /memory-stats
claude-md-block.md           the block appended to ~/.claude/CLAUDE.md
install.sh                   copy, merge, append, command, gitignore
HOW-TO-SETUP.md              build/verify runbook, written for Claude Code
LICENSE                      MIT
```

---

## Verification status

| | |
|---|---|
| `SessionStart` injection | Verified end-to-end — a real headless session repeated a token planted in the memo and the newest commit subject. |
| `SessionEnd` logging | Verified end-to-end; real payload captured, row written with the correct `reason`. |
| `Stop` memo check | All eight decision branches verified. Confirmed it does not displace an existing `Stop` hook. |
| Backup retention | Verified: 8 stale + 1 new → newest 5 kept; `CE_KEEP_BACKUPS=2` honoured. |
| `PreCompact` backup | Verified through the exact registered command line with realistic Windows-escaped payloads, both field spellings, and malformed input. **A real interactive `/compact` has not been observed** — headless `-p` mode does not compact, so that last link is untested. Run `/compact` once and check `.claude/memory/backups/`. |
| Fresh clone | LF endings intact, `bash -n` clean on all scripts. |
