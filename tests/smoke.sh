#!/usr/bin/env bash
# Smoke tests for the hooks: every scenario the docs promise, end to end, in a
# throwaway directory. Run from anywhere: bash tests/smoke.sh
set -u
HOOKS=$(cd "$(dirname "$0")/../hooks" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
PASS=0 FAIL=0

ok()   { PASS=$((PASS+1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
check() { # check <description> <want-exit> <got-exit>
  [ "$2" = "$3" ] && ok "$1" || fail "$1 (want exit $2, got $3)"
}

start() { # start <cwd> [session-id] -> runs SessionStart, output on stdout
  printf '{"session_id":"%s","transcript_path":"","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' \
    "${2:-cafe0123beef}" "$1" | bash "$HOOKS/session-start-context.sh"
}
stop() { (cd "$1" && bash "$HOOKS/stop-memo-check.sh" 2>"$WORK/stderr"); }

# --- git repo ----------------------------------------------------------------
R="$WORK/MyPlugin"
mkdir -p "$R" && git -C "$WORK" init -q "$R" && git -C "$R" commit -q --allow-empty -m init

# 1. no memo exists: an old PROJECT_CONTEXT.md is neither injected nor renamed
mkdir -p "$R/.claude/memory"
printf '# MyPlugin — Context
- old content
' > "$R/.claude/memory/PROJECT_CONTEXT.md"
OUT=$(start "$R")
case "$OUT" in *"old content"*) fail "no memo injected";; *) ok "no memo injected";; esac
[ -f "$R/.claude/memory/MyPlugin_Context.md" ] && fail "no memo created" || ok "no memo created"
rm -f "$R/.claude/memory/PROJECT_CONTEXT.md"

# 2. read-only session: memory files alone never count as project change
stop "$R"; check "silent when only .claude/memory changed" 0 $?

# 3. project changed, no note: nags once, naming the note
touch "$R/feature.txt"
stop "$R"; check "nags when the note is missing" 2 $?
grep -q "wrote no session note" "$WORK/stderr" && grep -q "cafe0123" "$WORK/stderr"   && ok "nag names the note file" || fail "nag names the note file"
stop "$R"; check "nags only once per session" 0 $?

# 4. note written: silent
rm -f "$R/.claude/memory/.session"
start "$R" > /dev/null
touch "$R/feature2.txt"; sleep 1
mkdir -p "$R/.claude/memory/sessions"
echo "# did things" > "$R/.claude/memory/sessions/Session_Context_untitled_cafe0123.md"
stop "$R"; check "silent when the note exists" 0 $?

# 5. earlier sessions are listed without this session's own note
for i in 1 2 3; do printf '# topic %s\n' "$i" > "$R/.claude/memory/sessions/Session_Context_t${i}_0000000${i}.md"; done
OUT=$(start "$R")
case "$OUT" in *"Session_Context_t1_00000001.md — topic 1"*) ok "lists earlier notes with titles";; \
  *) fail "lists earlier notes with titles";; esac
# Only the archive block counts: the instruction footer names the own note too.
ARCH=$(printf '%s\n' "$OUT" | sed -n '/^## Earlier sessions/,/^Read one/p')
case "$ARCH" in *"untitled_cafe0123"*) fail "own note stays off the list";; \
  *) ok "own note stays off the list";; esac

# --- plain directory (no git) ------------------------------------------------
D="$WORK/plain"
mkdir -p "$D"
start "$D" > /dev/null
[ -f "$D/.claude/memory/.session" ] && ok "works in a plain directory" || fail "works in a plain directory"
stop "$D"; check "plain dir: silent with no changes" 0 $?
sleep 1; touch "$D/notes.txt"
stop "$D"; check "plain dir: nags on a changed file" 2 $?

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
