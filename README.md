<div align="center">

# 🧠 Context Engine

**Automatic background compression for Claude Code conversation history.**

A local daemon watches your session transcripts, and once a threshold is hit, it summarizes older history via the Anthropic API into a rolling, self-contained summary. Claude pulls it back in via MCP instead of re-reading everything — and it's injected automatically on resume.

[![Node](https://img.shields.io/badge/node-%E2%89%A520-339933?logo=node.js&logoColor=white)](https://nodejs.org)
[![TypeScript](https://img.shields.io/badge/TypeScript-strict-3178C6?logo=typescript&logoColor=white)](https://www.typescriptlang.org)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-plugin-D97757?logo=anthropic&logoColor=white)](https://code.claude.com/docs/en/plugins)
[![License](https://img.shields.io/badge/license-MIT-blue)](#license)

</div>

---

## Why

Long Claude Code sessions bloat the context window. Native `/compact` helps but is manual, blocking, and lossy. Context Engine runs a separate process that watches your transcript in the background, and once a threshold is crossed, quietly compresses the older backlog into a structured summary — no interruption, nothing lost (it's still in SQLite, retrievable any time).

```
Fable 5 | my-project | ctx 62.3k 31% | CE backlog 4.1k · ✓ 2m ago · saved 41.7k
```
*(statusline, live)*

## What it actually does

| ✅ Real | ❌ Not possible (and not faked) |
|---|---|
| Fully automatic, non-blocking background compression via a detached daemon process | A plugin **cannot shrink the live context window** of the running session — only native `/compact` frees tokens in the active conversation |
| Rolling summaries per session — each compression merges the previous summary with new backlog, tagged with the exact transcript line range it covers | Plugins can't ship a statusline component directly — one settings entry activates the bundled script |
| Retrieval via MCP tools (`get_compressed_context`, `search_history`, `force_compress`, `get_status`) | `PreCompact` can't alter what native `/compact` produces — Context Engine only bookkeeps it |
| Automatic summary injection on `claude --resume` | |
| Cross-session, cross-project search over everything ever compressed | |
| Statusline: live context size + compression state + tokens saved | |

Think of it as a **parallel memory layer**, not a replacement for `/compact`. It makes `/compact` and `/clear` safe (nothing is lost) and gives you cross-session memory on top.

## Architecture

```
Claude Code session
 ├─ SessionStart hook ── registers session (id, transcript path, cwd) + starts daemon
 │                        on --resume: injects latest summary into context automatically
 ├─ PostToolUse hook ─── async watchdog: respawns daemon if it died (throttled, 30s)
 ├─ PreCompact hook ──── records native /compact events for bookkeeping
 ├─ SessionEnd hook ──── unregisters session
 ├─ MCP server ───────── get_compressed_context · search_history · force_compress · get_status
 └─ statusline ───────── reads live status JSON, renders ctx + backlog + saved tokens

Daemon (detached Node process, singleton via PID lockfile)
 ├─ polls registered transcripts every 2s
 ├─ tracks backlog tokens/messages since the last compression
 ├─ threshold hit → summarizes via Anthropic API (rolling merge with previous summary)
 └─ writes summaries to SQLite + per-session status JSON

Data — ~/.claude/context-engine/
 ├─ config.json          your settings (optional, hot-reloaded)
 ├─ context-engine.db    SQLite — all summaries, indexed by session + project
 ├─ sessions/<id>.json   session registry (written by hooks)
 ├─ status/<id>.json     live status for statusline/MCP
 └─ daemon.log / daemon.lock
```

## Install

Requires **Node.js ≥ 20**.

```bash
git clone https://github.com/QDHShamiro/Context-Engine.git
cd Context-Engine
npm install
npm run build        # -> dist/
```

Build **before** installing the plugin — Claude Code copies the plugin directory (including `dist/` and `node_modules/`) into its plugin cache.

Then, inside Claude Code:

```
/plugin marketplace add <path-to-Context-Engine>
/plugin install context-engine@context-engine-market
```

Restart the session. The `SessionStart` hook now registers every new session and starts the daemon automatically.

### Statusline (recommended)

```bash
npm run install-statusline
```

Sets `statusLine` in `~/.claude/settings.json` to the bundled script (prints your previous setting first, so you can restore it). Manual alternative:

```json
{
  "statusLine": {
    "type": "command",
    "command": "node \"<path-to-Context-Engine>/dist/statusline.js\"",
    "padding": 0
  }
}
```

### API key

The daemon calls the Anthropic API directly — it's a separate process, so Claude Code's own login isn't usable here.

```bash
setx ANTHROPIC_API_KEY sk-ant-...        # Windows, user-level
# or add "apiKey": "sk-ant-..." to ~/.claude/context-engine/config.json
```

Without a key everything still runs; compressions fail with a clear error (visible in `daemon.log` and the statusline) and retry after a cooldown.

## Configuration

`~/.claude/context-engine/config.json` — all optional, hot-reloaded by the daemon:

| Key | Default | Meaning |
|---|---|---|
| `tokenThreshold` | `50000` | Compress once the uncompressed backlog exceeds ~this many tokens (estimated, chars/4) |
| `messageThreshold` | `30` | …or this many messages since the last compression |
| `keepRecentMessages` | `10` | Newest messages that are never compressed |
| `minCompressMessages` | `8` | Minimum backlog beyond `keepRecentMessages` before compressing |
| `model` | `"claude-haiku-4-5"` | Compression model — any Anthropic model id |
| `maxSummaryTokens` | `2500` | Max tokens per generated summary |
| `apiKey` | `null` | Anthropic API key (falls back to `ANTHROPIC_API_KEY`) |
| `failureCooldownMinutes` | `5` | Wait after a failed compression before retrying |
| `idleExitMinutes` | `45` | Daemon exits after this much inactivity with zero sessions (hooks restart it on demand) |
| `debug` | `false` | Extra logging |

Env overrides: `CE_DATA_DIR` (data directory location), `CE_FAKE_COMPRESS=1` (deterministic offline summaries — used by the test suite).

## Usage

Runs entirely on its own. Manual controls when you want them:

| Command / tool | Effect |
|---|---|
| `/context-engine:status` | Sessions, backlog, compressions, daemon state |
| `/context-engine:compress` | Force a compression right now |
| `/context-engine:recall` | Load the latest summary into Claude's context |
| MCP `get_compressed_context` | Latest summary (Claude also calls this itself when useful) |
| MCP `search_history` | Full-text search across every stored summary — cross-session memory |
| `npm run daemon:once` | One manual daemon pass in a terminal, for debugging |

**Recommended workflow** for very long sessions: let Context Engine compress in the background, and when the live context gets tight, run native `/compact` — the SQLite summary guarantees nothing is truly lost, and `/context-engine:recall` restores detail on demand.

## Testing

```bash
npm run smoke
```

Offline end-to-end test, no API key required — simulates a transcript, runs the daemon pipeline twice with `CE_FAKE_COMPRESS=1`, and asserts: summary rows written, rolling ranges stay contiguous, status/saved-tokens tracked correctly, search works, statusline renders. **16 checks.**

<details>
<summary>Full manual test plan</summary>

1. **Offline smoke test** — `npm run smoke` (above).
2. **Real trigger test** — lower the thresholds in `~/.claude/context-engine/config.json`:
   ```json
   { "tokenThreshold": 3000, "messageThreshold": 6 }
   ```
   Start a new session, chat ~8 turns, watch the statusline flip `CE compressing…` → `saved …`. Verify with `/context-engine:status` and `~/.claude/context-engine/daemon.log`.
3. **Recall test** — `/context-engine:recall` in the same session; Claude should replay the key facts. Then `/clear`, start fresh, run `/context-engine:recall` again (falls back to project-level lookup).
4. **Resume test** — exit and `claude --resume` — the summary is injected automatically at session start.
5. **DB inspection**:
   ```bash
   node -e "const D=require('better-sqlite3');const os=require('os');const p=require('path');const db=new D(p.join(os.homedir(),'.claude','context-engine','context-engine.db'));console.log(db.prepare('SELECT id,session_id,from_line,to_line,raw_tokens,summary_tokens,model,created_at FROM summaries').all())"
   ```

</details>

## Troubleshooting

| Symptom | Fix |
|---|---|
| Statusline shows `CE starting…` forever | Daemon not running or session not registered — check `daemon.log` and `/hooks` |
| `CE error: no API key` | Configure the key (see [API key](#api-key)) |
| Changed the code but nothing updates | `npm run build`, then reinstall/update the plugin — the cache copy only refreshes on version bump or reinstall (statusline updates live, since it's referenced from this directory) |
| `better-sqlite3` install fails | Needs a prebuilt binary for your Node major version — upgrade Node or `npm rebuild better-sqlite3` |
| Daemon suspected dead | Any tool call in any session respawns it (`PostToolUse` watchdog), or run `npm run daemon` manually |

## Project layout

```
context-engine/
├── .claude-plugin/
│   ├── plugin.json          # plugin manifest
│   └── marketplace.json     # local marketplace entry
├── hooks/hooks.json         # SessionStart / PostToolUse / PreCompact / SessionEnd
├── commands/                # /context-engine:status|compress|recall
├── .mcp.json                # MCP server registration
└── src/
    ├── daemon/daemon.ts     # background compression loop
    ├── hooks/               # hook entry points
    ├── mcp/server.ts        # MCP tool server
    ├── lib/                 # config, db, transcript parsing, compressor, registry, status
    └── statusline.ts
```

## License

MIT
