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

# This session's own note file, named after the session's own title. Renamed in
# place if the session has been retitled since the last start.
SFILE=$(ce_session_file "$MEM")

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
  ARCHIVE=$(ls -1t "$SDIR"/Session_Context_*.md 2>/dev/null | while IFS= read -r f; do
    [ "$(basename "$f")" = "$SFILE" ] && continue
    printf '%s — %s\n' "$(basename "$f")" \
      "$(sed -n 's/^# *//p;/^# /q' "$f" 2>/dev/null | head -1)"
  done | head -6)
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

# The standing instruction rides along here rather than in CLAUDE.md: a plugin
# cannot write to the user's CLAUDE.md, and the skill only loads once triggered.
# Two lines is the price of the memo being maintained at all.
# A memo over budget quietly taxes every future session start; say so exactly
# once, here, where the size is already known.
MEMO_LINES=$(printf '%s' "$LOG" | wc -l)
if [ "$MEMO_LINES" -gt 70 ]; then
  echo
  echo "_The memo above is $MEMO_LINES lines — over its ~60-line budget. Compress it this session:"
  echo "move reasoning into session notes, keep only conclusions, delete anything no longer true._"
fi

echo
echo "_Context Engine. Keep .claude/memory/PROJECT_CONTEXT.md current as you work — one line per"
echo "finished feature, fix or decision: what and why. Detail belongs in this session's own note,"
echo ".claude/memory/sessions/$SFILE. Load the \`project-memory\` skill before writing either._"
exit 0
