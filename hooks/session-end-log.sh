#!/usr/bin/env bash
# SessionEnd hook. Appends one line per session to the project's session log.
set -u
SELF=$0; case "$SELF" in [A-Za-z]:*) SELF=$(cygpath -u "$SELF" 2>/dev/null || printf %s "$SELF");; esac
. "$(dirname "$SELF")/_lib.sh"

ROOT=$(ce_root)
ce_debug "$ROOT"
SID=$CE_session_id
REASON=$CE_session_end_reason
FILE=$(ce_memdir "$ROOT")/SESSION_LOG.md

[ -f "$FILE" ] || printf '# Session log\n\n| ended | project | session | reason |\n|---|---|---|---|\n' > "$FILE"
printf '| %s | %s | %s | %s |\n' \
  "$(date '+%Y-%m-%d %H:%M')" "$(basename "$ROOT")" "${SID:-?}" "${REASON:-?}" >> "$FILE"

exit 0
