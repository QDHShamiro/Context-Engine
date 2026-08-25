#!/usr/bin/env bash
# PreCompact hook. Copies the full transcript aside before context is compacted.
# Must never exit non-zero: exit 2 would block the compaction.
set -u
SELF=$0; case "$SELF" in [A-Za-z]:*) SELF=$(cygpath -u "$SELF" 2>/dev/null || printf %s "$SELF");; esac
. "$(dirname "$SELF")/_lib.sh"

ROOT=$(ce_root)
ce_debug "$ROOT"
SRC=$(ce_unix "$CE_transcript_path")
TRIGGER=$CE_compaction_trigger

if [ -n "$SRC" ] && [ -f "$SRC" ]; then
  DIR=$(ce_memdir "$ROOT")/backups
  mkdir -p "$DIR" 2>/dev/null
  STAMP=$(date +%Y%m%d-%H%M%S)
  cp "$SRC" "$DIR/${STAMP}-${TRIGGER:-unknown}.jsonl" 2>/dev/null || true
fi

exit 0
