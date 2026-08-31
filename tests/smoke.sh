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

# 1. old memo name is migrated and its content injected
mkdir -p "$R/.claude/memory"
printf '# MyPlugin — Context\n- old content\n' > "$R/.claude/memory/PROJECT_CONTEXT.md"
OUT=$(start "$R")
[ -f "$R/.claude/memory/MyPlugin_Context.md" ] && ok "migrates PROJECT_CONTEXT.md to <project>_Context.md" \
  || fail "migrates PROJECT_CONTEXT.md to <project>_Context.md"
case "$OUT" in *"old content"*) ok "injects the memo";; *) fail "injects the memo";; esac
case "$OUT" in *"MyPlugin_Context.md current as you work"*) ok "instruction names the memo";; \
  *) fail "instruction names the memo";; esac

# 2. read-only session: memory files alone never count as project change
stop "$R"; check "silent when only .claude/memory changed" 0 $?

# 3. project changed, nothing recorded: nags once, naming both files
touch "$R/feature.txt"
stop "$R"; check "nags when memo and note are missing" 2 $?
grep -q "MyPlugin_Context.md" "$WORK/stderr" && grep -q "session's note" "$WORK/stderr" \
  && ok "nag names both missing files" || fail "nag names both missing files"
stop "$R"; check "nags only once per session" 0 $?

# 4. memo updated but no note: next session nags for the note only
rm -f "$R/.claude/memory/.session"
start "$R" > /dev/null
touch "$R/feature2.txt"; sleep 1
touch "$R/.claude/memory/MyPlugin_Context.md"
stop "$R"; check "nags when only the note is missing" 2 $?
grep -q "session's note" "$WORK/stderr" && ! grep -q "the memo" "$WORK/stderr" \
  && ok "nag names only the note" || fail "nag names only the note"

# 5. memo and note both written: silent
rm -f "$R/.claude/memory/.session"
start "$R" > /dev/null
touch "$R/feature3.txt"; sleep 1
touch "$R/.claude/memory/MyPlugin_Context.md"
echo "# did things" > "$R/.claude/memory/sessions/Session_Context_untitled_cafe0123.md"
stop "$R"; check "silent when memo and note are both current" 0 $?

# 6. oversized memo draws the compression warning
{ echo "# MyPlugin — Context"; seq 1 75 | sed 's/^/- line /'; } > "$R/.claude/memory/MyPlugin_Context.md"
case "$(start "$R")" in *"over its ~60-line budget"*) ok "warns on an over-budget memo";; \
  *) fail "warns on an over-budget memo";; esac

# 7. earlier sessions are listed without this session's own note
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
