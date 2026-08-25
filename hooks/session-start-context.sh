#!/usr/bin/env bash
# SessionStart hook. Prints the project memo, the recent commits, and an index of
# the archived per-session notes. Plain stdout from SessionStart is injected into
# Claude's context, so everything printed here is what Claude starts out knowing.
set -u
SELF=$0; case "$SELF" in [A-Za-z]:*) SELF=$(cygpath -u "$SELF" 2>/dev/null || printf %s "$SELF");; esac
. "$(dirname "$SELF")/_lib.sh"

ROOT=$(ce_root)
ce_debug "$ROOT"
MEM=$(ce_memdir "$ROOT")
CTX="$MEM/PROJECT_CONTEXT.md"
SDIR="$MEM/sessions"
LOG=""

# This session's own note file. Named so it sorts chronologically and so the
# session id stays traceable back to the transcript under ~/.claude/projects.
SID_SHORT=$(printf '%s' "${CE_session_id:-unknown}" | cut -c1-8)
SFILE="Session_Context_$(date +%Y-%m-%d)_${SID_SHORT}.md"

# Stamp the start of the working session: the Stop hook compares the memo's mtime
# and the repo's HEAD against this to decide whether anything went unrecorded.
# Compaction restarts the session but not the work, so its stamp is left alone.
if [ "$CE_session_start_reason" != compact ]; then
  printf '%s\n%s\n' "$CE_session_id" "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)" \
    > "$MEM/.session" 2>/dev/null || true
fi

[ -f "$CTX" ] && LOG=$(cat "$CTX")
COMMITS=$(git -C "$ROOT" log -5 --format='%h %ad %s' --date=short 2>/dev/null)

# Index of the archived session notes: name plus its own title line, so Claude
# can tell which one is worth opening without any of them being loaded.
ARCHIVE=""
if [ -d "$SDIR" ]; then
  ARCHIVE=$(ls -1t "$SDIR"/Session_Context_*.md 2>/dev/null | head -6 | while IFS= read -r f; do
    [ "$(basename "$f")" = "$SFILE" ] && continue
    printf '%s — %s\n' "$(basename "$f")" \
      "$(sed -n 's/^# *//p;/^# /q' "$f" 2>/dev/null | head -1)"
  done)
fi

# Nothing to say -> say nothing, so a scratch directory costs zero tokens.
[ -n "$LOG" ] || [ -n "$COMMITS" ] || exit 0

if [ -n "$LOG" ]; then
  # Record the injection. Counting what actually happened is the only honest
  # basis for a savings figure; everything else is a hypothetical.
  printf '%s %s\n' "$(date +%s)" "$(( $(printf '%s' "$LOG" | wc -c) / 4 ))" \
    >> "$MEM/.starts" 2>/dev/null || true
  echo "$LOG"
else
  echo "# Project memory — $(basename "$ROOT")"
fi

if [ -n "$COMMITS" ]; then
  echo
  echo "## Recent commits"
  echo "$COMMITS"
fi

if [ -n "$ARCHIVE" ]; then
  echo
  echo "## Earlier sessions"
  echo "$ARCHIVE"
  echo "Read one from .claude/memory/sessions/ when you need the detail behind an entry above."
fi

echo
echo "_Injected by Context Engine. Rolling state goes in .claude/memory/PROJECT_CONTEXT.md;"
echo "this session's notes go in .claude/memory/sessions/$SFILE._"
exit 0
