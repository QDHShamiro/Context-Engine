#!/usr/bin/env bash
# SessionStart hook. Prints the project's memory file plus recent commits.
# Plain stdout from SessionStart is injected into Claude's context.
set -u
SELF=$0; case "$SELF" in [A-Za-z]:*) SELF=$(cygpath -u "$SELF" 2>/dev/null || printf %s "$SELF");; esac
. "$(dirname "$SELF")/_lib.sh"

ROOT=$(ce_root)
ce_debug "$ROOT"
CTX="$ROOT/.claude/memory/PROJECT_CONTEXT.md"
LOG=""

# Stamp the start of the working session: the Stop hook compares the memo's mtime
# and the repo's HEAD against this to decide whether anything went unrecorded.
# Compaction restarts the session but not the work, so its stamp is left alone.
if [ "$CE_session_start_reason" != compact ]; then
  printf '%s\n%s\n' "$CE_session_id" "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)" \
    > "$(ce_memdir "$ROOT")/.session" 2>/dev/null || true
fi

[ -f "$CTX" ] && LOG=$(cat "$CTX")
COMMITS=$(git -C "$ROOT" log -5 --format='%h %ad %s' --date=short 2>/dev/null)

# Nothing to say -> say nothing, so empty projects cost zero tokens.
[ -n "$LOG" ] || [ -n "$COMMITS" ] || exit 0

if [ -n "$LOG" ]; then
  echo "$LOG"
else
  echo "# Project memory — $(basename "$ROOT")"
fi
if [ -n "$COMMITS" ]; then
  echo
  echo "## Recent commits"
  echo "$COMMITS"
fi
echo
echo "_(Injected by the SessionStart memory hook. Keep .claude/memory/PROJECT_CONTEXT.md current as you work.)_"
exit 0
