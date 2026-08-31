#!/usr/bin/env bash
# Stop hook. Blocks once per session if the project changed but the memo did
# not, so the memo is a rule rather than a suggestion.
#
# Deliberately reads no stdin and spawns no python: this runs at the end of every
# assistant turn, so it stays at a couple of cheap calls. Everything it needs is
# in the working directory and the stamp SessionStart left behind.
set -u

# Project root. Git toplevel when there is one; otherwise the nearest ancestor
# already holding a .claude/memory, so this works in a plain directory too.
ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$ROOT" ]; then
  d=$PWD
  while [ -n "$d" ] && [ "$d" != / ]; do
    if [ -d "$d/.claude/memory" ]; then ROOT=$d; break; fi
    case "$d" in [A-Za-z]:|/[A-Za-z]) break ;; esac
    d=${d%/*}
  done
fi
[ -n "$ROOT" ] || exit 0

MEM="$ROOT/.claude/memory"
STAMP="$MEM/.session"

[ -f "$STAMP" ] || exit 0
[ -f "$MEM/.no-nag" ] && exit 0
grep -qx nagged "$STAMP" 2>/dev/null && exit 0

# The rolling memo is named after the project directory; a memo still under the
# old fixed name counts until SessionStart migrates it.
CTX="$MEM/$(basename "$ROOT")_Context.md"
[ -f "$CTX" ] || { [ -f "$MEM/PROJECT_CONTEXT.md" ] && CTX="$MEM/PROJECT_CONTEXT.md"; }

# Both files are required once the project moved: the memo touched since this
# session began, and a note for this session (its id is line 1 of the stamp).
SID=$(sed -n 1p "$STAMP" 2>/dev/null | cut -c1-8)
NOTE=$(ls "$MEM/sessions/"*_"${SID:-unknown}".md 2>/dev/null | head -1)
MEMO_OK=; [ -f "$CTX" ] && [ "$CTX" -nt "$STAMP" ] && MEMO_OK=1
[ -n "$MEMO_OK" ] && [ -n "$NOTE" ] && exit 0

# Only worth asking if the session actually moved the project.
if git -C "$ROOT" rev-parse HEAD >/dev/null 2>&1; then
  # The memory dir is excluded: the hooks' own stamp files and session notes
  # must never count as "the project changed", or an untracked .claude/memory
  # nags on every session in repos that don't gitignore it.
  DIRTY=$(git -C "$ROOT" status --porcelain -- . ':(exclude).claude/memory' 2>/dev/null | head -1)
  HEAD_NOW=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)
  HEAD_THEN=$(sed -n 2p "$STAMP" 2>/dev/null || true)
  [ -n "$DIRTY" ] || [ "$HEAD_NOW" != "$HEAD_THEN" ] || exit 0
else
  # No repo to ask, so ask the filesystem: anything written under the project
  # since the session started. Depth-bounded and stops at the first hit, because
  # this runs every turn.
  CHANGED=$(find "$ROOT" -maxdepth 3 -type f -newer "$STAMP" \
              -not -path '*/.claude/*' -not -path '*/.git/*' \
              -print -quit 2>/dev/null)
  [ -n "$CHANGED" ] || exit 0
fi

printf 'nagged\n' >> "$STAMP"
MISS=""
[ -n "$MEMO_OK" ] || MISS="the memo $CTX (one line per entry: what and why)"
[ -n "$NOTE" ] || MISS="${MISS:+$MISS and }this session's note in $MEM/sessions/ (the detail and reasoning)"
echo "This session changed the project but $MISS was not updated. Follow the \`project-memory\` skill and update it now, then finish." >&2
exit 2
