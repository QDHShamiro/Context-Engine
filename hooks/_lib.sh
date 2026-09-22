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
CE_title=""
CE_title_slug=""

# Probe, don't just look up: on Windows `python3` is usually the Microsoft Store
# app-execution stub, which resolves on PATH but refuses to run anything.
CE_PY=false
for _c in python3 python py; do
  if "$_c" -c "" >/dev/null 2>&1; then CE_PY=$_c; break; fi
done

CE_INPUT=$(cat)

eval "$(printf '%s' "$CE_INPUT" | "$CE_PY" -c '
import json, os, re, shlex, sys, unicodedata
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

# The session title lives in the transcript as repeated {"type":"ai-title"}
# records; the last one wins. Reading it here is free - we are already parsing.
title = ""
tp = d.get("transcript_path") or ""
try:
    if tp and os.path.isfile(tp):
        n = os.path.getsize(tp)
        with open(tp, "rb") as fh:
            if n > 1 << 20:
                fh.seek(-(1 << 20), 2)
                fh.readline()
            for line in fh.read().decode("utf-8", "replace").splitlines():
                if "ai-title" in line:
                    try:
                        title = json.loads(line).get("aiTitle") or title
                    except Exception:
                        pass
except Exception:
    pass

slug = unicodedata.normalize("NFKD", title).encode("ascii", "ignore").decode()
slug = re.sub(r"[^A-Za-z0-9]+", "-", slug).strip("-").lower()[:40].strip("-")
print("CE_title=%s" % shlex.quote(title))
print("CE_title_slug=%s" % shlex.quote(slug or "untitled"))
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

# ce_root -> project root. Git toplevel when there is one; otherwise the nearest
# ancestor already holding a .claude/memory, so a plain directory behaves the
# same as a repo. Falls back to the cwd itself.
ce_root() {
  local d top
  d=$(ce_unix "$CE_cwd")
  [ -n "$d" ] && [ -d "$d" ] || d=$PWD

  if top=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null) && [ -n "$top" ]; then
    printf '%s' "$top"
    return 0
  fi

  top=$d
  while [ -n "$top" ] && [ "$top" != / ]; do
    if [ -d "$top/.claude/memory" ]; then printf '%s' "$top"; return 0; fi
    case "$top" in [A-Za-z]:|/[A-Za-z]) break ;; esac
    top=${top%/*}
  done
  printf '%s' "$d"
}

# ce_memdir <root> -> <root>/.claude/memory, created on demand
ce_memdir() {
  local m="$1/.claude/memory"
  mkdir -p "$m" 2>/dev/null
  printf '%s' "$m"
}

# ce_session_file <memdir> -> filename of this session's note, renaming an
# existing one when the session has since been retitled. The short session id
# stays in the name, so the file is still findable whatever the title becomes.
ce_session_file() {
  local dir="$1/sessions" sid want cur
  sid=$(printf '%s' "${CE_session_id:-unknown}" | cut -c1-8)
  mkdir -p "$dir" 2>/dev/null
  cur=$(ls -1 "$dir"/*_"${sid}".md 2>/dev/null | head -1)

  # A title Claude Code has not assigned yet must never rename a file that
  # already carries one - the transcript is simply unreadable from here.
  if [ -z "${CE_title_slug:-}" ] || [ "$CE_title_slug" = untitled ]; then
    if [ -n "$cur" ]; then printf '%s' "$(basename "$cur")"; else
      printf '%s' "Session_Context_untitled_${sid}.md"; fi
    return 0
  fi

  want="Session_Context_${CE_title_slug}_${sid}.md"
  if [ -n "$cur" ] && [ "$(basename "$cur")" != "$want" ]; then
    mv -f "$cur" "$dir/$want" 2>/dev/null || want=$(basename "$cur")
  fi
  printf '%s' "$want"
}

# ce_debug <root> -> append the raw hook input to hook-input.log, but only while
# <root>/.claude/memory/.debug exists. A hook that fails is otherwise silent, and
# this is the only way to see what the payload actually looked like.
ce_debug() {
  [ -f "$1/.claude/memory/.debug" ] || return 0
  printf '%s\n' "$CE_INPUT" >> "$1/.claude/memory/hook-input.log"
}
