# HOW-TO-SETUP

A runbook for Claude Code — installing, verifying, extending, or rebuilding this hook set without
rediscovering the traps. Read it before touching `hooks/` or `install.sh`.

`README.md` explains what the system does for a human. This file is about getting it *right*.

---

## 1. Ground truth — do not guess these

The published hook documentation and the shipping binary disagree in places, and the differences
are silent failures, not errors. Everything below was verified against **Claude Code v2.1.245** by
capturing real payloads.

### Matchers

| Event | Valid matcher values | Notes |
|---|---|---|
| `SessionStart` | `startup` `resume` `clear` `compact` `fork` | |
| `PreCompact` | `manual` `auto` | |
| `SessionEnd` | `clear` `resume` `logout` `prompt_input_exit` `other` | |
| `Stop` | **none** — takes no matcher, always fires | Omit the `matcher` key entirely |

Matcher syntax: `*`, `""`, or omitted matches all. A value containing only letters, digits, `_`,
`-`, spaces, `,` and `|` is an exact-match list separated by `|` or `,`. Anything else is treated
as an unanchored JavaScript regex. Comma separators need v2.1.191+; `|` works everywhere, so
prefer it.

### Payload field names

**The binary sends the short names. The docs list the long ones. Read both.**

| Purpose | v2.1.245 sends | Docs say |
|---|---|---|
| why the session started | `source` | `session_start_reason` |
| what triggered compaction | `trigger` | `compaction_trigger` |
| why the session ended | `reason` | `session_end_reason` |

Common fields, present and reliable on all three payload-bearing events: `session_id`,
`transcript_path`, `cwd`, `hook_event_name`. A real captured `SessionStart` payload:

```json
{"session_id":"5d204d76-...","transcript_path":"C:\\Users\\you\\.claude\\projects\\C--…\\5d204d76-….jsonl","cwd":"C:\\Users\\you\\project","hook_event_name":"SessionStart","source":"startup"}
```

### The session title

Claude Code writes the session's title into the transcript as repeated records:

```json
{"type":"ai-title","aiTitle":"Loschen project komplett","sessionId":"332e8c72-..."}
```

They are appended, not replaced, so **the last one wins**. There is no central index to read it
from - the transcript is the source. Read it from the tail like everything else.

### Output semantics

| Event | stdout | exit 2 |
|---|---|---|
| `SessionStart` | **added to Claude's context** | not honoured; stderr shown to user |
| `PreCompact` | debug log only | **blocks compaction** |
| `SessionEnd` | debug log only | not honoured |
| `Stop` | debug log only | **blocks stopping**, stderr goes back to Claude as the reason |

Two consequences that shape the whole design: `SessionStart` is the only place to inject context,
and `PreCompact` must never exit non-zero.

### Timeouts

Default is 600s for `command` hooks, except `UserPromptSubmit` at 30s. `SessionEnd` hooks share a
**1.5-second budget** unless a longer per-hook `timeout` raises it (up to 60s). Always set an
explicit `timeout` on `SessionEnd`.

---

## 2. Preconditions

Run these before building anything. Each one has bitten this project.

```bash
# Bash, and its absolute path for the Windows command line
command -v bash && cygpath -m "$(command -v bash).exe" 2>/dev/null

# A python that actually runs — NOT just one that resolves
for c in python3 python py; do "$c" -c "print('$c ok')" 2>/dev/null; done

# Git
git --version

# Claude Code version — matcher and field behaviour depend on it
claude --version
```

If `python3` prints nothing but `command -v python3` succeeds, you have hit the Microsoft Store
app-execution stub. It exits 49 without running. **Probe interpreters by execution, never by
lookup.**

---

## 3. Build order

Interfaces before implementations; verify each layer before building on it.

1. **`hooks/_lib.sh`** — payload parsing and path handling. Everything else depends on it.
2. **One hook script per event.** Each sources `_lib.sh`, does one thing, exits explicitly.
3. **`install.sh`** — copy, merge, append, gitignore. Idempotent.
4. **`claude-md-block.md`** — the instruction appended to `~/.claude/CLAUDE.md`.
5. **`hooks/memory-stats.sh`** and the `/memory-stats` command file the installer writes to
   `~/.claude/commands/`. Not a hook; it lives in `hooks/` only so the installer's `cp hooks/*.sh`
   picks it up.
6. **Verify** (section 7) before committing.

### Two memory files, not one

`<project>_Context.md` is injected in full at every session start, so it must stay short.
`sessions/Session_Context_<title>_<id>.md` is only ever *listed* - name and title line - so it can
hold the detail. That asymmetry is the design: the archive is what earns the rolling memo the right
to be brief. Never inject the archive itself; the moment you do, the saving is gone.

Name the note from the session's title and keep the short session id in the filename, so it stays
findable across renames. Reconcile at session start *and* session end, since a title usually only
settles partway through.

### Measuring the saving

Count what happened. A total over every session ever recorded includes the ones that predate the
install and never saw a memo - that is a hypothesis presented as a measurement, and it is the
number a reader will quote. Log each real injection and sum over the log; a fresh install should
report zero and count up.

Do not estimate the baseline, and do not put a number in the README you cannot regenerate.

Every assistant record in a transcript carries a real `usage` block. The tokens a session was
holding when it ended is `input_tokens + cache_read_input_tokens + cache_creation_input_tokens`
from the last such record — that is the cost of `claude --resume`, and therefore the honest
baseline for what the memo replaces. Only the memo side is estimated (characters ÷ 4), and the
output says so.

Read the transcript from the tail. They reach 50 MB; seek to the last 1 MB, drop the partial first
line, and scan only lines containing `"usage"`.

Map a project root to its transcript directory by reading the `cwd` field out of a transcript, not
by reconstructing Claude Code's directory slug. The slug encoding is undocumented and a wrong
guess reports zero sessions instead of failing.

State the boundary of the claim in the output itself: only the cold start improves, what a session
accumulates while running is unchanged, and the memo is a summary rather than a replacement for
the transcript.

### `_lib.sh` contract

Sourced, never executed. On return it must have set, as shell variables, every field any hook
needs, plus these helpers:

| | |
|---|---|
| `CE_<field>` | one per payload field, empty string when absent — pre-initialised so `set -u` is safe |
| `CE_INPUT` | the raw stdin, kept for `ce_debug` |
| `ce_unix <path>` | Windows path → POSIX path |
| `ce_root` | project root: git toplevel, else the nearest ancestor holding `.claude/memory`, else the cwd |
| `CE_title`, `CE_title_slug` | the session's current title and a filename-safe slug of it, read from the transcript in the same call |
| `ce_memdir <root>` | `<root>/.claude/memory`, created on demand |
| `ce_session_file <memdir>` | this session's note filename, renaming an existing one when the title changed |
| `ce_debug <root>` | append `CE_INPUT` to `hook-input.log`, only while `.debug` exists |

**Parse the whole payload in one interpreter call.** Not one call per field. This is not a
micro-optimisation: with four separate spawns the `SessionEnd` hook missed its budget on roughly
half of runs and wrote nothing, silently. Emit `KEY=<shlex.quote(value)>` lines and `eval` them.

### Script skeleton

Every hook script starts the same way:

```bash
#!/usr/bin/env bash
set -u
SELF=$0; case "$SELF" in [A-Za-z]:*) SELF=$(cygpath -u "$SELF" 2>/dev/null || printf %s "$SELF");; esac
. "$(dirname "$SELF")/_lib.sh"

ROOT=$(ce_root)
ce_debug "$ROOT"
```

The `$0` conversion is required. When `cmd.exe` invokes `bash.exe "C:\...\hook.sh"`, `dirname` on
a backslash path returns `.`, and sourcing `_lib.sh` fails — silently, because hooks swallow
stderr.

---

## 4. Shipping it as a plugin

A plugin is the primary distribution; `install.sh` is the fallback for anyone not using the plugin
system. Layout Claude Code discovers on its own - none of it is referenced from `plugin.json`:

```
.claude-plugin/plugin.json       name, version, description, author, license, keywords
.claude-plugin/marketplace.json  owner + one entry with source "./"
hooks/hooks.json                 the four hook registrations
commands/*.md                    slash commands
skills/<name>/SKILL.md           skills, loaded on description match
```

Two things differ from a settings.json install:

**Paths go through `${CLAUDE_PLUGIN_ROOT}`**, and each hook entry sets `"shell": "bash"`. That
removes the whole Windows `bash.exe` problem - no absolute interpreter path to discover, no
`cmd.exe` quoting.

**A plugin cannot write to the user's `CLAUDE.md`.** Standing instructions have to arrive some
other way, and there are only two: a skill, which loads on description match, and the `SessionStart`
output, which is unconditional. Split them - the two-line rule that must always be in force rides
in the injection, and the full ruleset lives in the skill for when the memo is actually being
written. Do not put the whole ruleset in the injection; it is paid for at every session start.

Validate before publishing - it catches manifest and component errors without an install:

```bash
claude plugin validate .                          # marketplace manifest
claude plugin validate .claude-plugin/plugin.json # plugin manifest
claude plugin validate skills                     # skills
claude plugin validate commands                   # commands
```

Both install paths register the same hooks, so make the standalone installer refuse to run when it
sees the plugin enabled. Doubling every hook is silent, and silent is the worst failure mode here.

---

## 5. Registration

Write the command line so it works from `cmd.exe`:

```
"<abs path to bash.exe>" "<abs path to script.sh>"
```

Both quoted, both forward slashes, obtained with `cygpath -m`. Get the bash path from `$BASH`,
appending `.exe` if `"$BASH.exe"` is executable — `cygpath -m /usr/bin/bash` yields a path with no
extension, which `cmd.exe` will not run.

On Linux and macOS register the script path alone.

**Merge, never overwrite.** Load `settings.json`, keep every hook group whose serialised form does
not contain your marker string, append yours, write back. Copy to `.bak` first. Reuse of a single
marker (`context-memory`) across all entries is what makes re-running the installer safe.

---

## 6. Mistakes already made — do not repeat

Each of these cost a debugging cycle here.

**A bracket pattern with a backslash does not survive tool escaping.** `[\\/]` written through a
JSON tool parameter arrives as `[\/]`, which in a `case` glob matches only `/`. Windows paths then
never match and `cygpath` never runs. Detect a Windows path with `[A-Za-z]:*` instead — no
backslash, no escaping layer, and `cygpath` normalises either separator anyway.

**Hand-written JSON test fixtures are usually invalid.** `printf '{"p":"C:\\tmp\\x"}'` yields
`"C:\tmp\x"` — `\t` is a tab escape and `\x` is illegal, so `json.load` throws and every field
comes back empty. This looks exactly like a broken parser. Generate fixtures with
`python -c "import json;print(json.dumps({...}))"`.

**`python3` resolving is not `python3` working.** See section 2.

**Silence is the default failure mode.** Every hook swallows stderr and most exit 0 regardless.
Build the debug affordance (`.debug` → `hook-input.log`) *first*; it is how you find out that a
payload field is named `source` and not `session_start_reason`.

**`SessionEnd` does not reliably fire in headless `-p` mode.** Roughly half of runs, from a
teardown race. It is not a defect in the hook. Verify `SessionEnd` by direct invocation plus one
captured real payload, not by counting headless runs.

**Headless mode does not compact.** Filling context with large reads, giant prompts, or
`--continue` chains up to a 1.7 MB transcript produced no compaction. There is no way to force
`PreCompact` from `-p`. Verify the script and the registered command line directly, then have a
human run `/compact` once.

**CRLF breaks the scripts.** Add `*.sh text eol=lf` to `.gitattributes` in the same commit as the
scripts. Git Bash carries a trailing `\r` into variable values, which corrupts paths and
comparisons in ways that look like logic bugs.

**A degraded read must not overwrite good data.** The rename reconciler first reverted notes to
`untitled` whenever the transcript could not be read - turning "I don't know the title" into "the
title is nothing". When a lookup fails, leave what is already there alone.

**Keep terminal output under ~58 columns.** The first report ran wide and lost its right-hand
column in a normal terminal, which is exactly where the units and percentages were.

**A `Stop` hook that blocks needs its own loop guard.** Do not rely on a payload flag. Persist a
marker (here: a `nagged` line appended to `.session`) and check it first. Gate blocking on real
evidence of work — dirty tree or moved `HEAD` — or it fires after every read-only question. And
exclude the hook's own output (`:(exclude).claude/memory`), or an untracked memory dir counts as
evidence and it fires every session.

**A `Stop` hook runs after every turn.** Budget accordingly: no stdin read, no interpreter spawn.
Derive the project root from `$PWD` via `git rev-parse --show-toplevel`.

---

## 7. Verification protocol

Do not report done before all of these pass. `mkjson` builds valid fixtures:

```bash
mkjson() { python -c "import json,sys;print(json.dumps(dict(a.split('=',1) for a in sys.argv[1:])))" "$@"; }
R=$(cygpath -w "$PWD" 2>/dev/null || printf %s "$PWD")
```

**1. Each hook, both field spellings.** Short names and documented names must behave identically.

```bash
mkjson "cwd=$R" "session_id=t1" "source=startup"   | bash hooks/session-start-context.sh
mkjson "cwd=$R" "session_id=t1" "session_start_reason=startup" | bash hooks/session-start-context.sh
```

**2. Malformed and empty stdin.** Must exit 0, must not hang, must not create garbage.

```bash
printf 'not json' | bash hooks/pre-compact-backup.sh; echo "exit=$?  # must be 0"
printf ''         | bash hooks/session-start-context.sh; echo "exit=$?"
```

**3. Project root from a subdirectory.** Pass a nested `cwd` and confirm the hook still finds the
repo root.

**4. Empty project.** No git, no memo → `SessionStart` must print nothing and exit 0.

**5. Through the registered command line**, not through `bash hooks/…`. This is what proves the
`bash.exe` path, the quoting, and `$0` normalisation:

```bash
mkjson "cwd=$R" "session_id=t1" "trigger=manual" \
  | "C:/Program Files/Git/usr/bin/bash.exe" "$HOME/.claude/hooks/context-memory/pre-compact-backup.sh"
```

**6. The merge preserved foreign hooks.** List every registered hook and confirm pre-existing ones
survived:

```bash
python -c "import json,io;h=json.load(io.open('$HOME/.claude/settings.json',encoding='utf-8'))['hooks'];\
[print('%-14s %-24s %s'%(e,g.get('matcher','(none)'),x['command'][:70])) for e,gs in h.items() for g in gs for x in g['hooks']]"
```

**7. Real session, real injection.** The only test that proves the whole chain. Plant a token in a
throwaway project's memo and make a real session repeat it:

```bash
claude -p --model sonnet "Do not use tools. If a project memory block is in your context, reply with the MAGIC token in it, else NONE."
```

**8. Real payload capture.** `touch .claude/memory/.debug`, run a session, read `hook-input.log`,
confirm the field names match what the parser expects.

**9. Renames, all three ways.** Retitled session renames the note; an unreadable transcript leaves
the existing name alone; a session with no note yet creates nothing.

**10. Savings on an empty log.** With no recorded injections the report must say zero, not fall
back to a figure derived from sessions that never used the memo.

**11. Fresh clone.** Line endings and syntax:

```bash
git clone -q <url> /tmp/verify && cd /tmp/verify
for f in hooks/*.sh install.sh; do grep -qU $'\r' "$f" && echo "$f CRLF-BAD"; bash -n "$f" || echo "$f SYNTAX"; done
```

**12. Re-run `install.sh`.** Entry count must not grow; the `CLAUDE.md` block must not duplicate.

---

## 8. Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| All fields empty | Invalid JSON fixture, or the Store `python3` stub | Generate fixtures with `json.dumps`; probe interpreters by execution |
| Hook produces nothing, exit 0 | `_lib.sh` not found — `dirname` on a backslash `$0` | Normalise `$0` with `cygpath -u` first |
| `SessionEnd` writes intermittently | Multiple interpreter spawns exceeding the 1.5s budget | One parse call; set an explicit `timeout` |
| Windows path never converted | `[\\/]` collapsed to `[\/]` by escaping | Match `[A-Za-z]:*` |
| Compaction refuses to run | A `PreCompact` hook exited non-zero | Guard everything, end with `exit 0` |
| Claude never stops | Blocking `Stop` hook with no loop guard | Persist a fired-marker and check it first |
| Existing hooks vanished | `settings.json` overwritten instead of merged | Restore from `.bak`; filter by marker and append |
| Scripts fail after clone | CRLF | `*.sh text eol=lf` in `.gitattributes` |
| Note reverts to `untitled` | A failed title read treated as an empty title | Leave the existing name when the lookup fails |
| Report loses its right column | Output wider than the terminal | Keep it under ~58 columns |
| Hook times out | Process startup under load | Raise that entry's `timeout` |

---

## 9. Hard rules

1. `PreCompact` ends with `exit 0`. Always. Exit 2 costs the user their session.
2. One interpreter spawn per hook. Parse the whole payload once.
3. `Stop` hooks: no stdin, no interpreter, and a persisted loop guard.
4. Read both the short and the documented field names.
5. Probe interpreters by running them.
6. Merge into `settings.json`; back it up first; key idempotence off a single marker string.
7. Register hooks by absolute path, through an absolute interpreter path on Windows.
8. Ship the debug affordance with the first version, not after the first mystery.
9. Never claim a leg is verified because a neighbouring leg passed. If `/compact` was never
   observed, say so.
10. Every performance number is measured from data on disk and reproducible by a command the
    README names. State what was compared and what the claim excludes.
11. Count what happened, never what would have. Zero is an honest first reading.
12. Only the rolling memo is injected. The session archive is listed, never loaded.
13. A failed read leaves existing data alone. Never let "unknown" overwrite "known".
14. Run `claude plugin validate` on every manifest and component directory before publishing.
15. Two install paths must never both register. The standalone installer refuses when the plugin
    is enabled.
16. Git is a bonus, not a requirement. Find the project root by walking up for `.claude/memory`
    when there is no repo, and answer "did anything change?" from file mtimes instead of
    `git status`. A hook that silently does nothing outside a repo is a hook most people never
    see work.
