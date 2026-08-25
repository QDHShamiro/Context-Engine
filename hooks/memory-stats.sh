#!/usr/bin/env bash
# What the memo saves at session start, measured from the usage records Claude
# Code already writes into its transcripts. No estimates on the baseline side.
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
import glob, io, json, os, sys

ALL  = "--all" in sys.argv
JSON = "--json" in sys.argv
args = [a for a in sys.argv[1:] if not a.startswith("--")]
CWD  = os.path.abspath(args[0]) if args else os.getcwd()

CFG      = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")
PROJECTS = os.path.join(CFG, "projects")


def norm(p):
    return os.path.normcase(os.path.abspath(p)).replace("\\", "/").rstrip("/")


def median(xs):
    xs = sorted(xs)
    return xs[len(xs) // 2] if xs else 0


def session_context(path):
    """Tokens the model was holding when this session ended.

    Read from the tail: the largest context is in the last assistant record and
    these transcripts run to tens of megabytes."""
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
        size = os.path.getsize(path)
        with io.open(path, "rb") as fh:
            if size > 1 << 20:
                fh.seek(-(1 << 20), os.SEEK_END)
                fh.readline()                    # drop the partial first line
            best = scan(fh.read().decode("utf-8", "replace"))
        if best or size > 20 << 20:
            return best
        with io.open(path, encoding="utf-8", errors="replace") as fh:
            return scan(fh.read())
    except Exception:
        return 0


def project_dirs():
    """(project root, [transcripts]) per recorded project.

    The root comes from the cwd Claude Code wrote into the transcript, rather
    than from guessing how it encodes a path into a directory slug."""
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


def memo(root):
    p = os.path.join(root, ".claude", "memory", "PROJECT_CONTEXT.md")
    if not os.path.exists(p):
        return 0, 0
    text = io.open(p, encoding="utf-8", errors="replace").read()
    return max(1, len(text) // 4), len(text.splitlines())


def backups(root):
    files = glob.glob(os.path.join(root, ".claude", "memory", "backups", "*.jsonl"))
    return len(files), sum(os.path.getsize(f) for f in files)


def measure(root, files):
    sizes = [x for x in (session_context(f) for f in files) if x > 0]
    tok, lines = memo(root)
    med = median(sizes)
    n, b = backups(root)
    return {
        "project": os.path.basename(root.rstrip("/\\")) or root,
        "root": root,
        "sessions": len(sizes),
        "baseline_median": med,
        "memo_tokens": tok,
        "memo_lines": lines,
        "saved_tokens": max(0, med - tok) if tok and med else 0,
        "saved_percent": round((med - tok) * 100.0 / med, 1) if tok and med else 0,
        "ratio": round(med / tok, 1) if tok and med else 0,
        "backup_files": n,
        "backup_bytes": b,
        "_sizes": sizes,
    }


def human(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return "%.0f %s" % (n, unit)
        n /= 1024.0
    return "%.1f TB" % n


if ALL:
    rows = [measure(root, files) for root, files in project_dirs()]
else:
    want = norm(CWD)
    files = next((f for root, f in project_dirs() if norm(root) == want), [])
    rows = [measure(CWD, files)]

every = [s for r in rows for s in r["_sizes"]]
memos = [r["memo_tokens"] for r in rows if r["memo_tokens"]]
summary = {
    "projects": len([r for r in rows if r["sessions"]]),
    "sessions": len(every),
    "baseline_median": median(every),
    "memo_median": median(memos),
}
_m, _b = summary["memo_median"], summary["baseline_median"]
summary["ratio"]         = round(_b / _m, 1) if _m and _b else 0
summary["saved_tokens"]  = max(0, _b - _m) if _m and _b else 0
summary["saved_percent"] = round((_b - _m) * 100.0 / _b, 1) if _m and _b else 0
# Every recorded session, had it started from a memo instead of a resume.
summary["saved_total"]   = sum(max(0, s - _m) for s in every) if _m else 0

for r in rows:
    r.pop("_sizes")

if JSON:
    print(json.dumps({"summary": summary, "projects": rows}, indent=2))
    sys.exit(0)

shown = [r for r in rows if r["memo_tokens"] or (not ALL and r["sessions"])]
print()

if not shown and not ALL:
    print("  No memo and no recorded sessions here yet.")
    print("  Seed one:  mkdir -p .claude/memory && $EDITOR .claude/memory/PROJECT_CONTEXT.md")
    print()
    sys.exit(0)

for r in sorted(shown, key=lambda r: -r["ratio"]):
    print("  %s" % r["project"])
    if r["memo_tokens"]:
        print("    memo                 %7s tokens   %d lines"
              % ("{:,}".format(r["memo_tokens"]), r["memo_lines"]))
    else:
        print("    memo                       -        not seeded yet")
    print("    sessions             %7d" % r["sessions"])
    if r["baseline_median"]:
        print("    resume baseline      %7s tokens   median session-end context"
              % "{:,}".format(r["baseline_median"]))
    if r["ratio"]:
        print("    saved per start      %7s tokens   %s%% of the cold start"
              % ("{:,}".format(r["saved_tokens"]), r["saved_percent"]))
        print("    cold start           %7s          smaller" % ("%sx" % r["ratio"]))
    if r["backup_files"]:
        print("    backups              %7d files   %s"
              % (r["backup_files"], human(r["backup_bytes"])))
    print()

if ALL:
    unseeded = len([r for r in rows if r["sessions"] and not r["memo_tokens"]])
    print("  machine-wide")
    print("    sessions             %7s          across %d projects"
          % ("{:,}".format(summary["sessions"]), summary["projects"]))
    print("    resume baseline      %7s tokens   median session-end context"
          % "{:,}".format(summary["baseline_median"]))
    if summary["memo_median"]:
        print("    memo                 %7s tokens   median where one exists"
              % "{:,}".format(summary["memo_median"]))
        print("    saved per start      %7s tokens   %s%% of the cold start"
              % ("{:,}".format(summary["saved_tokens"]), summary["saved_percent"]))
        print("    cold start           %7s          smaller" % ("%sx" % summary["ratio"]))
        print("    saved across all  %10s tokens   had every session started from a memo"
              % "{:,}".format(summary["saved_total"]))
    if unseeded:
        print("    %d project(s) have sessions but no memo yet." % unseeded)
    print()

print("  Baseline is what resuming the previous session costs: the tokens that session")
print("  held when it ended, read from the transcript's own usage records. Memo size is")
print("  estimated at 4 characters per token. The memo is a summary, not a replacement")
print("  for the transcript - .claude/memory/backups/ keeps that.")
print()
PY
