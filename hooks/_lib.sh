#!/usr/bin/env bash
# Shared helpers for the context-memory hooks. Sourced by the hook scripts,
# never executed on its own.
#
# The whole hook input is parsed in a single python call and exposed as CE_<field>.
# One interpreter spawn per hook matters: SessionEnd runs on a short budget and
# process startup on Windows is the expensive part.

CE_session_id=""
CE_transcript_path=""
CE_cwd=""
CE_hook_event_name=""
CE_session_start_reason=""
CE_compaction_trigger=""
CE_session_end_reason=""

# Probe, don't just look up: on Windows `python3` is usually the Microsoft Store
# app-execution stub, which resolves on PATH but refuses to run anything.
CE_PY=false
for _c in python3 python py; do
  if "$_c" -c "" >/dev/null 2>&1; then CE_PY=$_c; break; fi
done

CE_INPUT=$(cat)

eval "$(printf '%s' "$CE_INPUT" | "$CE_PY" -c '
import json, shlex, sys
# The published schema and the shipping binary disagree on the "why" fields:
# v2.1.245 sends source/trigger/reason, the docs say the *_reason names.
# Accept both, newest name first, so this keeps working either way.
KEYS = (
    ("session_id",           ("session_id",)),
    ("transcript_path",      ("transcript_path",)),
    ("cwd",                  ("cwd",)),
    ("hook_event_name",      ("hook_event_name",)),
    ("session_start_reason", ("session_start_reason", "source")),
    ("compaction_trigger",   ("compaction_trigger", "trigger")),
    ("session_end_reason",   ("session_end_reason", "reason")),
)
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
if not isinstance(d, dict):
    d = {}
for out, names in KEYS:
    val = next((str(d[n]) for n in names if d.get(n)), "")
    print("CE_%s=%s" % (out, shlex.quote(val)))
' 2>/dev/null)"

# ce_unix <path> -> POSIX path. A leading drive letter means a Windows path,
# whichever separator it uses; cygpath normalises both. Passthrough elsewhere.
ce_unix() {
  case "$1" in
    [A-Za-z]:*)
      if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else printf '%s' "$1"; fi
      ;;
    *) printf '%s' "$1" ;;
  esac
}

# ce_root -> project root: git toplevel of the hook's cwd, else the cwd itself
ce_root() {
  local d
  d=$(ce_unix "$CE_cwd")
  [ -n "$d" ] && [ -d "$d" ] || d=$PWD
  git -C "$d" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$d"
}

# ce_memdir <root> -> <root>/.claude/memory, created on demand
ce_memdir() {
  local m="$1/.claude/memory"
  mkdir -p "$m" 2>/dev/null
  printf '%s' "$m"
}

# ce_debug <root> -> append the raw hook input to hook-input.log, but only while
# <root>/.claude/memory/.debug exists. A hook that fails is otherwise silent, and
# this is the only way to see what the payload actually looked like.
ce_debug() {
  [ -f "$1/.claude/memory/.debug" ] || return 0
  printf '%s\n' "$CE_INPUT" >> "$1/.claude/memory/hook-input.log"
}
