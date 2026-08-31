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

<p align="center">
  <strong>99.8% smaller pick-up &nbsp;·&nbsp; ~800 tokens instead of ~150,000</strong><br>
  <sub>Measured from the token counts Claude Code already writes into its own transcripts — not
  estimated, not extrapolated. <code>/memory-stats</code> counts only the session starts that
  actually used it, so a fresh install reports zero and counts up.</sub>
</p>

---

## The problem

You open a repo you last touched three weeks ago. Claude knows nothing about it.

So you either spend ten minutes re-explaining, or it spends them re-reading files. `claude --resume`
replays the old session instead — the whole conversation, every tool result, at full price. On this
machine that averages **145,000 tokens** before a single new word is typed.

None of that is state. It is the transcript of how you arrived at the state.

## What it does

```
  WITHOUT                                WITH
  ─────────────────────────────────      ─────────────────────────────────
  claude --resume                        claude
    replays the entire session             reads a 50-line memo
    390,666 tokens                         944 tokens
    most of it tool output                 all of it current state
                                           99.8% less
```

Four hooks keep a short Markdown memo per project and inject it at session start. The detail lives
in per-session notes that are **listed but never loaded** — so the archive costs nothing, and the
memo it buys stays short.

```
  session start ──→  memo + last 5 commits injected          ~800 tokens
        │            earlier session notes listed by title
        │
        ├──→  you work; Claude keeps the memo current as it goes
        │
   /compact ──→  full transcript copied to backups/ first
        │
    /clear ──→  chat context dropped, memo injected again    ~800 tokens
        │       ← this is the reset button
        │
  session end ──→  one row in SESSION_LOG.md
```

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

Registers the same four hooks directly in `~/.claude/settings.json` and appends the memo rules to
`~/.claude/CLAUDE.md` instead of shipping them as a skill.

**Use one or the other, not both** — they register the same hooks and you would get each of them
twice. `install.sh` refuses to run when it sees the plugin enabled.

What it does:

1. Copies `hooks/*.sh` to `~/.claude/hooks/context-memory/`.
2. Works out the command line to register. On Windows the hook runs through `cmd.exe`, which cannot
   execute a `.sh`, so the command becomes `"<abs path to bash.exe>" "<abs path to script>"`.
3. Backs up `~/.claude/settings.json`, then **merges** its four entries in. Any hook group whose
   command does not contain `context-memory` is left untouched — existing hooks survive.
4. Appends the memo-maintenance block to `~/.claude/CLAUDE.md`, between HTML markers.
5. Installs the `/memory-stats` slash command.
6. Adds `.claude/memory/` to git's global excludes.

Re-running replaces only its own entries. `CLAUDE_CONFIG_DIR` is honoured throughout.
</details>

**Requirements:** Claude Code v2.1.191+ and Python 3. On Windows, the Git Bash that ships with
Git for Windows. Git itself is optional — a plain directory works the same, it just has no commit
log to inject.

**Ships with:** four hooks, the `/memory-stats` command, and the `project-memory` skill that holds
the rules for writing the memo.

---

## The four hooks

| | Fires on | What it does |
|---|---|---|
| **inject** | `SessionStart` — `startup\|clear\|compact\|resume` | Prints the memo, the last 5 commits, and an index of earlier session notes. `SessionStart` stdout goes straight into Claude's context. |
| **backup** | `PreCompact` — `manual\|auto` | Copies the full transcript to `backups/` before compaction discards it. Keeps the newest 5. |
| **log** | `SessionEnd` — all | One row per session: time, project, id, why it ended. |
| **enforce** | `Stop` | Once per session, if the repo changed but the memo or this session's note did not follow, blocks and asks. |

The `Stop` hook only fires when the project actually moved — a dirty tree or a new `HEAD` in a
repo, a file written since the session began anywhere else. Changes under `.claude/memory` itself
never count, so the hook's own files can't trigger it. A read-only question never triggers it. Opt out per project with `touch .claude/memory/.no-nag`.

---

## The numbers

```
  Context Engine

    memo                  944   tokens, 54 lines
    a resume          390,666   tokens
                    ---------
    saved per start   389,722   99.8% less, 413.8x

    starts                  2   since today
    saved so far      779,444   tokens

  All projects

    with a memo             2   of 22
    starts                  3   since today

  ============================================
   SAVED BY CONTEXT ENGINE         853,980
  ============================================
```

**Every figure is measured, and the honest one starts small.**

- **The cold number is real.** Every assistant record in a transcript carries a `usage` block. The
  script reads `input_tokens + cache_read_input_tokens + cache_creation_input_tokens` from the last
  one — that *is* what resuming costs.
- **The total counts what happened.** Each session start that actually receives the memo appends a
  line to `.claude/memory/.starts`, and the total sums only those. A figure covering every session
  ever recorded would be a hypothesis dressed up as a measurement.
- **Only the memo side is estimated**, at four characters per token.

**What it does not claim:** only the *pick-up* changes. What a session grows to while you work is
the same either way, and the memo summarises rather than replaces — the full transcript is still in
`backups/` when you need the detail.

`/memory-stats` reports this *and* brings the memo up to date in the same run. The command that
tells you the memo is worth having is also the one that writes it.

---

## The memo

Two files, and the difference between them is the whole design:

| File | Injected every session start? | Therefore |
|---|---|---|
| `<project>_Context.md` | **Yes** | Must stay short. You pay for it forever. |
| `sessions/Session_Context_<title>_<id>.md` | No — only its name and title are listed | Can hold the detail. Written once, read on demand. |

Both are maintained by Claude, not by you.

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

**The rules, and why each one exists:**

| Rule | Because |
|---|---|
| Written in English, whatever you speak | Re-read at every session start for the life of the project — the tokenisation gap compounds over hundreds of starts |
| One line per entry: **what** and **why**, never *how* | The code already says how, and a memo describing implementation is wrong within a week |
| Stale entries get **deleted**, not corrected underneath | A memo that reads as current and isn't is worse than none |
| Under ~60 lines | Past that you have reinvented the transcript, at transcript prices |
| No code, diffs, or logs | Git has the changelog, and the last 5 commits are injected right beside it |

Session notes take everything that does not fit: the approach that failed and why, the constraint
found the hard way, the reasoning a one-line decision can only conclude. They cost nothing because
they are never loaded — only listed, so Claude knows one exists and can open it when an entry above
is too terse to act on. Each is named after its session's title, and follows a rename.

---

## Using it well

**`/clear` is the reset button.** It drops the chat context; the hook puts the memo straight back.
You carry on in the same terminal with the state and none of the accumulation. Nothing is lost —
the transcript stays under `~/.claude/projects/`, and `claude --resume` still reaches it.

**Keep it short — that is the entire trade.** Every line you add to the memo is a line you pay for
in every future session in that repo.

**Write it when the work lands.** A memo assembled from memory in the last two minutes of a session
is the one that gets the reasons wrong, and the reasons are the only part worth keeping.

**Seed old repos by hand.** A project you have worked in for months starts with an empty memo — the
first session there gets only the commit log. Write four lines and let Claude take over:

```bash
mkdir -p .claude/memory && cat > .claude/memory/<project>_Context.md <<'EOF'
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

**`SESSION_LOG.md` finds the session you want back.** It maps a timestamp to a session id;
`claude --resume <id>` does the rest.

**`backups/` recovers what compaction dropped.** After a `/compact` the exact commands and outputs
are gone from context but still sitting in the newest backup. It is JSONL — grep it.

---

## Configuration

No config file. Three switches:

| | |
|---|---|
| `touch .claude/memory/.no-nag` | Stop the memo check from blocking in this project |
| `touch .claude/memory/.debug` | Append every raw hook payload to `hook-input.log` |
| `CE_KEEP_BACKUPS` | Backups to keep. Default 5. Set it in `settings.json` under `env` |

<details>
<summary><b>Files it creates, and how to remove it</b></summary>

Per project, in `<project>/.claude/memory/`:

| | |
|---|---|
| `<project>_Context.md` | The rolling memo, named after the project directory. Injected every session start. Commit it. |
| `sessions/Session_Context_<title>_<id>.md` | One note per session. Listed at start, read on demand. Commit these too. |
| `SESSION_LOG.md` | One row per session. |
| `backups/` | Pre-compaction transcripts, newest 5. |
| `.starts` | One line per real injection. Backs the savings figure. |
| `.session` | Session stamp (id + HEAD) for the `Stop` check. |

**Uninstall (plugin):**

```
/plugin uninstall context-engine@context-engine
```

**Uninstall (`install.sh`):** it also touches `~/.claude/hooks/context-memory/`, four entries in
`settings.json`, the `/memory-stats` command, a block in `CLAUDE.md`, and the memory entries in the global
gitignore.

```bash
rm -rf ~/.claude/hooks/context-memory ~/.claude/commands/memory-stats.md
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
| `SessionStart` injection | Verified end-to-end — a real headless session repeated a token planted in the memo and the newest commit subject |
| `SessionEnd` logging | Verified end-to-end; real payload captured, row written with the correct reason |
| `Stop` memo check | All eight decision branches verified; confirmed it does not displace an existing `Stop` hook |
| Session-note naming | All three cases: a retitle renames, an unreadable transcript leaves the name alone, a session with no note creates nothing |
| Savings counting | Verified against a seeded `.starts` and an empty one, which reports zero rather than a hypothetical |
| Backup retention | 8 stale + 1 new → newest 5 kept; `CE_KEEP_BACKUPS=2` honoured |
| Fresh clone | LF endings intact, `bash -n` clean on every script |
| `PreCompact` backup | Verified through the exact registered command line with realistic Windows-escaped payloads, both field spellings, and malformed input. **A real interactive `/compact` has not been observed** — headless `-p` mode does not compact, so that last link is untested. |

</details>

---

<p align="center">
  <sub>MIT · Built for <a href="https://claude.com/claude-code">Claude Code</a></sub>
</p>
