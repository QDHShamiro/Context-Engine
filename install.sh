#!/usr/bin/env bash
# Installs the context-memory hooks into the user-level Claude Code config.
# Safe to re-run: it replaces its own entries and leaves everything else alone.
set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DEST="$CLAUDE_DIR/hooks/context-memory"

# This installs the same four hooks the plugin registers. Running both doubles
# every one of them, which is silent and confusing rather than loud.
if [ "${1:-}" != --force ] && grep -q '"context-engine@' "$CLAUDE_DIR/settings.json" 2>/dev/null; then
  echo "install: the context-engine plugin is already enabled and registers these same hooks." >&2
  echo "         Use one or the other. Pass --force to install anyway." >&2
  exit 1
fi

# Probe, don't just look up: on Windows `python3` is usually the Microsoft Store
# app-execution stub, which resolves on PATH but refuses to run anything.
PY=""
for c in python3 python py; do
  if "$c" -c "" >/dev/null 2>&1; then PY=$c; break; fi
done
[ -n "$PY" ] || { echo "install: need python3 on PATH" >&2; exit 1; }

# 1. scripts -----------------------------------------------------------------
mkdir -p "$DEST"
cp "$REPO"/hooks/*.sh "$DEST"/
chmod +x "$DEST"/*.sh
echo "hooks: installed to $DEST"

# 2. hook command lines ------------------------------------------------------
# Windows runs the hook through cmd.exe, which cannot execute a .sh directly,
# so the command invokes this very bash with mixed-mode (forward slash) paths.
if command -v cygpath >/dev/null 2>&1; then
  _b=${BASH:-$(command -v bash)}
  [ -x "${_b}.exe" ] && _b="${_b}.exe"
  BASH_EXE=$(cygpath -m "$_b")
  DEST_CMD=$(cygpath -m "$DEST")
  cmd_for() { printf '"%s" "%s/%s"' "$BASH_EXE" "$DEST_CMD" "$1"; }
else
  cmd_for() { printf '"%s/%s"' "$DEST" "$1"; }
fi

# 3. settings.json + CLAUDE.md ----------------------------------------------
"$PY" - "$CLAUDE_DIR/settings.json" "$CLAUDE_DIR/CLAUDE.md" "$REPO/claude-md-block.md" \
      "$(cmd_for session-start-context.sh)" \
      "$(cmd_for pre-compact-backup.sh)" \
      "$(cmd_for session-end-log.sh)" \
      "$(cmd_for stop-memo-check.sh)" <<'PY'
import io, json, os, shutil, sys

settings, claude_md, block_file = sys.argv[1:4]
start_cmd, compact_cmd, end_cmd, stop_cmd = sys.argv[4:8]
MARK = "context-memory"

# Stop takes no matcher: it always fires.
SPECS = [
    # clear is the point of the whole thing: /clear drops the chat context and
    # this puts the memo straight back, so it doubles as a reset button.
    ("SessionStart", "startup|clear|compact|resume", start_cmd, 15),
    ("PreCompact",   "manual|auto",            compact_cmd, 30),
    ("SessionEnd",   "*",                      end_cmd,     10),
    ("Stop",         None,                     stop_cmd,    10),
]

data = {}
if os.path.exists(settings):
    shutil.copyfile(settings, settings + ".bak")
    with io.open(settings, encoding="utf-8") as fh:
        data = json.load(fh)

hooks = data.setdefault("hooks", {})
for event, matcher, command, timeout in SPECS:
    kept = [g for g in hooks.get(event, []) if MARK not in json.dumps(g)]
    group = {"hooks": [{"type": "command", "command": command, "timeout": timeout}]}
    if matcher:
        group = dict(matcher=matcher, **group)
    kept.append(group)
    hooks[event] = kept

with io.open(settings, "w", encoding="utf-8") as fh:
    fh.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
print("settings: %s registered (backup: settings.json.bak)"
      % ", ".join(e for e, _, _, _ in SPECS))

BEGIN, END = "<!-- BEGIN context-memory -->", "<!-- END context-memory -->"
block = io.open(block_file, encoding="utf-8").read().strip()
cur = io.open(claude_md, encoding="utf-8").read() if os.path.exists(claude_md) else ""
if BEGIN in cur and END in cur:
    cur = cur[:cur.index(BEGIN)] + cur[cur.index(END) + len(END):]
io.open(claude_md, "w", encoding="utf-8").write(cur.rstrip() + "\n\n" + block + "\n")
print("CLAUDE.md: memory instruction block written")
PY

# 4. /memory-stats slash command ---------------------------------------------
mkdir -p "$CLAUDE_DIR/commands"
cat > "$CLAUDE_DIR/commands/memory-stats.md" <<CMD
---
description: Show what the project memo saves, and bring the memo up to date
allowed-tools: Bash(bash:*), Read, Write, Edit
---

!\`bash "$DEST/memory-stats.sh" \$ARGUMENTS\`

Show that output verbatim. The numbers come from the transcripts' own usage
records - do not recompute, round, or embellish them.

Then bring \`.claude/memory/PROJECT_CONTEXT.md\` in the current project up to date
with this session, without being asked again:

- Missing? Create it, using the structure and rules in the project-memory block
  of ~/.claude/CLAUDE.md.
- Present? Add what this session changed, delete entries that stopped being
  true rather than correcting them underneath, and refresh the Updated date.
- One line per entry, what and why, never how. Under ~60 lines total. No code,
  logs, or diffs.

Finish with a single line saying what you added or removed, or that the memo was
already current. The size shown above was measured before this update.
CMD
echo "command: /memory-stats installed"

# 5. keep .claude/memory out of every repo ------------------------------------
# Optional: the hooks work in directories that are not repos at all.
if ! command -v git >/dev/null 2>&1; then
  echo "git: not installed - skipping the global gitignore entry"
  echo
  echo "Done. Restart Claude Code (or start a new session) for the hooks to load."
  exit 0
fi
GI=$(git config --global core.excludesFile 2>/dev/null || true)
if [ -z "$GI" ]; then
  GI="~/.gitignore_global"
  git config --global core.excludesFile "$GI"
fi
GI_FILE=${GI/#\~/$HOME}
case "$GI_FILE" in [A-Za-z]:*) GI_FILE=$(cygpath -u "$GI_FILE") ;; esac
mkdir -p "$(dirname "$GI_FILE")"
touch "$GI_FILE"
grep -qxF '.claude/memory/' "$GI_FILE" || printf '.claude/memory/\n' >> "$GI_FILE"
echo "git: .claude/memory/ ignored globally via $GI_FILE"

echo
echo "Done. Restart Claude Code (or start a new session) for the hooks to load."
