#!/usr/bin/env bash
# What the memo saves when you pick a project back up, measured from the token
# counts Claude Code already writes into its own transcripts.
#
#   bash memory-stats.sh            this project
#   bash memory-stats.sh --all      every project, plus a machine-wide summary
#   bash memory-stats.sh --json     machine-readable
set -u

for _c in python3 python py; do
  if "$_c" -c "" >/dev/null 2>&1; then PY=$_c; break; fi
done
[ -n "${PY:-}" ] || { echo "memory-stats: need python3 on PATH" >&2; exit 1; }

exec "$PY" - "$@" <<'PY'
import glob, io, json, os, subprocess, sys, time

ALL  = "--all" in sys.argv
JSON = "--json" in sys.argv
args = [a for a in sys.argv[1:] if not a.startswith("--")]

CFG      = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")
PROJECTS = os.path.join(CFG, "projects")
TODAY    = time.strftime("%Y-%m-%d")


# ---------------------------------------------------------------- helpers ---

def norm(p):
    return os.path.normcase(os.path.abspath(p)).replace("\\", "/").rstrip("/")


def git_root(p):
    """The same definition of "project" the hooks use, so running this from a
    subdirectory still finds the sessions recorded at the repo root."""
    try:
        r = subprocess.run(["git", "-C", p, "rev-parse", "--show-toplevel"],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        out = r.stdout.decode("utf-8", "replace").strip()
        if r.returncode == 0 and out:
            return out
    except Exception:
        pass
    return p


def under(child, parent):
    c, p = norm(child), norm(parent)
    return c == p or c.startswith(p + "/")


def median(xs):
    xs = sorted(xs)
    return xs[len(xs) // 2] if xs else 0


def num(n):
    return "{:,}".format(int(n))


def size(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return "%.0f %s" % (n, unit)
        n /= 1024.0
    return "%.1f TB" % n


def day(ts):
    if not ts:
        return "-"
    d = time.strftime("%Y-%m-%d", time.localtime(ts))
    return "today" if d == TODAY else d


def span(first, last):
    if not first:
        return ""
    a, b = day(first), day(last)
    if a == b:
        return a if a == "today" else "on %s" % a
    return "%s to %s" % (a, b)


def plural(n, word):
    return "%d %s%s" % (n, word, "" if n == 1 else "s")


CWD = git_root(os.path.abspath(args[0]) if args else os.getcwd())


# --------------------------------------------------------------- measuring --

def session_context(path):
    """Tokens the model was holding when this session ended.

    Read from the tail: the largest context sits in the last assistant record
    and these transcripts reach tens of megabytes."""
    def scan(chunk):
        best = 0
        for line in chunk.splitlines():
            if '"usage"' not in line:
                continue
            try:
                u = json.loads(line)["message"]["usage"]
            except Exception:
                continue
            best = max(best, (u.get("input_tokens") or 0)
                            + (u.get("cache_read_input_tokens") or 0)
                            + (u.get("cache_creation_input_tokens") or 0))
        return best

    try:
        n = os.path.getsize(path)
        with io.open(path, "rb") as fh:
            if n > 1 << 20:
                fh.seek(-(1 << 20), os.SEEK_END)
                fh.readline()                    # drop the partial first line
            best = scan(fh.read().decode("utf-8", "replace"))
        if best or n > 20 << 20:
            return best
        with io.open(path, encoding="utf-8", errors="replace") as fh:
            return scan(fh.read())
    except Exception:
        return 0


def project_dirs():
    """(project root, [transcripts]) per recorded project.

    The root comes from the cwd Claude Code wrote into the transcript, not from
    guessing how it encodes a path into a directory name."""
    out = []
    for d in sorted(glob.glob(os.path.join(PROJECTS, "*"))):
        files = glob.glob(os.path.join(d, "*.jsonl"))
        if not files:
            continue
        cwd = None
        try:
            with io.open(files[0], encoding="utf-8", errors="replace") as fh:
                for _ in range(20):
                    line = fh.readline()
                    if not line:
                        break
                    cwd = json.loads(line).get("cwd")
                    if cwd:
                        break
        except Exception:
            pass
        if cwd:
            out.append((cwd, files))
    return out


def measure(root, files):
    sizes, stamps, disk = [], [], 0
    for f in files:
        try:
            disk += os.path.getsize(f)
            stamps.append(os.path.getmtime(f))
        except Exception:
            pass
        c = session_context(f)
        if c:
            sizes.append(c)

    memo_p = os.path.join(root, ".claude", "memory", "PROJECT_CONTEXT.md")
    memo_t = memo_l = memo_m = 0
    if os.path.exists(memo_p):
        text = io.open(memo_p, encoding="utf-8", errors="replace").read()
        memo_t, memo_l = max(1, len(text) // 4), len(text.splitlines())
        memo_m = os.path.getmtime(memo_p)

    bk = glob.glob(os.path.join(root, ".claude", "memory", "backups", "*.jsonl"))
    med = median(sizes)

    return {
        "project": os.path.basename(root.rstrip("/\\")) or root,
        "root": root,
        "sessions": len(sizes),
        "first": min(stamps) if stamps else 0,
        "last": max(stamps) if stamps else 0,
        "disk_bytes": disk,
        "biggest": max(sizes) if sizes else 0,
        "baseline_median": med,
        "memo_tokens": memo_t,
        "memo_lines": memo_l,
        "memo_updated": memo_m,
        "backup_files": len(bk),
        "backup_bytes": sum(os.path.getsize(f) for f in bk),
        "saved_tokens": max(0, med - memo_t) if memo_t and med else 0,
        "saved_percent": round((med - memo_t) * 100.0 / med, 1) if memo_t and med else 0,
        "ratio": round(med / memo_t, 1) if memo_t and med else 0,
        "_sizes": sizes,
    }


dirs = project_dirs()

if ALL:
    rows = [measure(root, files) for root, files in dirs]
    FALLBACK = False
else:
    # Sessions started in a subdirectory are recorded under that path, so take
    # everything at or below the project root, not just an exact match.
    files = [f for root, fs in dirs if under(root, CWD) for f in fs]
    rows = [measure(CWD, files)]
    # Nothing here yet: show the machine-wide picture rather than a dead end,
    # so the number the user came for is on screen either way.
    FALLBACK = not rows[0]["sessions"] and not rows[0]["memo_tokens"]
    if FALLBACK:
        rows = [measure(root, fs) for root, fs in dirs]

every    = [s for r in rows for s in r["_sizes"]]
memos    = [r["memo_tokens"] for r in rows if r["memo_tokens"]]
scored   = [r for r in rows if r["sessions"]]
med_base = median(every)
med_memo = median(memos)

summary = {
    "projects":       len(scored),
    "projects_memo":  len(memos),
    "sessions":       len(every),
    "first":          min([r["first"] for r in scored] or [0]),
    "last":           max([r["last"] for r in scored] or [0]),
    "disk_bytes":     sum(r["disk_bytes"] for r in rows),
    "biggest":        max([r["biggest"] for r in rows] or [0]),
    "baseline_median": med_base,
    "memo_median":    med_memo,
    "saved_tokens":   max(0, med_base - med_memo) if med_memo and med_base else 0,
    "saved_percent":  round((med_base - med_memo) * 100.0 / med_base, 1) if med_memo and med_base else 0,
    "ratio":          round(med_base / med_memo, 1) if med_memo and med_base else 0,
    # Every recorded session, had it started from a memo instead of a resume.
    "saved_total":    sum(max(0, s - med_memo) for s in every) if med_memo else 0,
}

for r in rows:
    r.pop("_sizes")

if JSON:
    print(json.dumps({"summary": summary, "projects": rows}, indent=2))
    sys.exit(0)


# ---------------------------------------------------------------- printing --

RULE = " " * 24 + "-" * 10


def row(label, value, note=""):
    print("    %-19s %10s   %s" % (label, value, note))


def comparison(cold, memo, saved, pct, ratio, cold_note, memo_note):
    row("picking up cold", num(cold), cold_note)
    row("picking up by memo", num(memo), memo_note)
    print(RULE)
    row("you save", num(saved), "%s%% less, %sx smaller" % (pct, ratio))


print()

if FALLBACK:
    print("  %s" % (os.path.basename(CWD.rstrip("/\\")) or CWD))
    print("    nothing recorded here yet - showing the machine-wide picture instead")
    print()
    shown = []
else:
    shown = [r for r in rows if r["memo_tokens"] or (not ALL and r["sessions"])]

for r in sorted(shown, key=lambda r: -r["ratio"]):
    print("  %s" % r["project"])
    print()
    row("sessions", r["sessions"], span(r["first"], r["last"]))
    if r["memo_tokens"]:
        row("memo", num(r["memo_tokens"]),
            "tokens, %s, updated %s" % (plural(r["memo_lines"], "line"), day(r["memo_updated"])))
    else:
        row("memo", "-", "none written here yet")
    if r["disk_bytes"]:
        row("transcripts", size(r["disk_bytes"]), "on disk")
    if r["backup_files"]:
        row("backups", r["backup_files"], "kept here, %s" % size(r["backup_bytes"]))
    if r["biggest"] and r["biggest"] != r["baseline_median"]:
        row("biggest session", num(r["biggest"]), "tokens")
    if r["ratio"]:
        print()
        comparison(r["baseline_median"], r["memo_tokens"], r["saved_tokens"],
                   r["saved_percent"], r["ratio"],
                   "tokens - what resuming the last session costs",
                   "tokens - your memo instead")
    print()

if ALL or FALLBACK:
    s = summary
    print("  Everything on this machine")
    print()
    row("projects", s["projects"],
        "%d with a memo, %d without" % (s["projects_memo"], s["projects"] - s["projects_memo"]))
    row("sessions", num(s["sessions"]), span(s["first"], s["last"]))
    row("transcripts", size(s["disk_bytes"]), "on disk under ~/.claude/projects")
    row("biggest session", num(s["biggest"]), "tokens")
    row("typical session", num(s["baseline_median"]), "tokens")
    if s["memo_median"]:
        print()
        comparison(s["baseline_median"], s["memo_median"], s["saved_tokens"],
                   s["saved_percent"], s["ratio"],
                   "tokens - a typical session, resumed",
                   "tokens - a typical memo instead")
        print()
        print("    Add every session up and that is %s tokens, if each had started"
              % num(s["saved_total"]))
        print("    from a memo instead of a resume.")
    if s["projects"] - s["projects_memo"]:
        print()
        print("    %s here with sessions but no memo yet."
              % plural(s["projects"] - s["projects_memo"], "project"))
    print()

if FALLBACK:
    print("  Seed a memo here and the same applies to this project:")
    print("    mkdir -p .claude/memory && $EDITOR .claude/memory/PROJECT_CONTEXT.md")
    print()

print("  Reading this: without a memo, the way back into a project is `claude --resume`,")
print("  which reloads everything that session was holding when it ended - the cold")
print("  number. With a memo you load the memo instead. Same starting point, that much")
print("  less to pay for. `/clear` is the button: it drops the chat context and the")
print("  memo goes straight back in.")
print()
print("  The cold number is not an estimate - Claude Code writes a token count into")
print("  every transcript and this reads the last one. Only the memo side is estimated,")
print("  at four characters per token. Only the pick-up changes: what a session grows")
print("  to while you work is the same either way, and the full transcript stays in")
print("  .claude/memory/backups/ when you need the detail back.")
print()
PY
