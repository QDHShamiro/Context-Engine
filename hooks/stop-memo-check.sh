#!/usr/bin/env bash
# Stop hook. Blocks once per session if the repo changed but the project memo did
# not, so the memo is a rule rather than a suggestion.
#
# Deliberately reads no stdin and spawns no python: this runs at the end of every
# assistant turn, so it stays at a couple of git calls. Everything it needs is in
# the working directory and the stamp SessionStart left behind.
set -u

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
MEM="$ROOT/.claude/memory"
STAMP="$MEM/.session"
CTX="$MEM/PROJECT_CONTEXT.md"

[ -f "$STAMP" ] || exit 0
[ -f "$MEM/.no-nag" ] && exit 0
grep -qx nagged "$STAMP" 2>/dev/null && exit 0

# Memo already touched since this session began -> nothing to ask for.
[ -f "$CTX" ] && [ "$CTX" -nt "$STAMP" ] && exit 0

# Only worth asking if the session actually moved the repo.
DIRTY=$(git -C "$ROOT" status --porcelain 2>/dev/null | head -1)
HEAD_NOW=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)
HEAD_THEN=$(sed -n 2p "$STAMP" 2>/dev/null || true)
[ -n "$DIRTY" ] || [ "$HEAD_NOW" != "$HEAD_THEN" ] || exit 0

printf 'nagged\n' >> "$STAMP"
echo "This session changed the repository but $CTX was not updated. Update it now (one line per entry: what and why, plus anything still open), then finish." >&2
exit 2
