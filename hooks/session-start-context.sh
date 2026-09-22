#!/usr/bin/env bash
# SessionStart hook. Prints the recent commits and an index of the per-session
# notes. Plain stdout from SessionStart is injected into Claude's context, so
# everything printed here is what Claude starts out knowing.
set -u
SELF=$0; case "$SELF" in [A-Za-z]:*) SELF=$(cygpath -u "$SELF" 2>/dev/null || printf %s "$SELF");; esac
. "$(dirname "$SELF")/_lib.sh"

ROOT=$(ce_root)
ce_debug "$ROOT"
MEM=$(ce_memdir "$ROOT")
SDIR="$MEM/sessions"

# This session's own note file, named after the session's own title. Renamed in
# place if the session has been retitled since the last start.
SFILE=$(ce_session_file "$MEM")

# Stamp the start of the working session: the Stop hook reads the session id and
# HEAD from here to decide whether the project changed without a session note.
# Compaction restarts the session but not the work, so its stamp is left alone.
if [ "$CE_session_start_reason" != compact ]; then
  printf '%s\n%s\n' "$CE_session_id" "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)" \
    > "$MEM/.session" 2>/dev/null || true
fi

COMMITS=$(git -C "$ROOT" log -5 --format='%h %ad %s' --date=short 2>/dev/null)

# Index of the session notes: name plus its own title line, so Claude can tell
# which one is worth opening without any of them being loaded.
ARCHIVE=""
if [ -d "$SDIR" ]; then
  ARCHIVE=$(ls -1t "$SDIR"/Session_Context_*.md 2>/dev/null | while IFS= read -r f; do
    [ "$(basename "$f")" = "$SFILE" ] && continue
    printf '%s — %s\n' "$(basename "$f")" \
      "$(sed -n 's/^# *//p;/^# /q' "$f" 2>/dev/null | head -1)"
  done | head -6)
fi

# Nothing to say -> say nothing, so a scratch directory costs zero tokens.
[ -n "$COMMITS" ] || [ -n "$ARCHIVE" ] || exit 0

echo "# Project memory — $(basename "$ROOT")"

if [ -n "$COMMITS" ]; then
  echo
  echo "## Recent commits"
  echo "$COMMITS"
fi

if [ -n "$ARCHIVE" ]; then
  echo
  echo "## Earlier sessions"
  echo "$ARCHIVE"
  echo "Read one from .claude/memory/sessions/ when you need its detail."
fi

echo
echo "_Context Engine. Write this session's note to .claude/memory/sessions/$SFILE as you work:"
echo "what changed, why, what failed, what is left open. Load the \`project-memory\` skill first._"
exit 0
