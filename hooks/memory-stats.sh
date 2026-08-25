#!/usr/bin/env bash
# What Context Engine has actually saved, counted from session starts that really
# got the memo, against token counts Claude Code writes into its own transcripts.
#
#   bash memory-stats.sh            this project
#   bash memory-stats.sh --all      every project with a memo
#   bash memory-stats.sh --json     machine-readable
set -u

for _c in python3 python py; do
  if "$_c" -c "" >/dev/null 2>&1; then PY=$_c; break; fi
done
[ -n "${PY:-}" ] || { echo "memory-stats: need python3 on PATH" >&2; exit 1; }

exec "$PY" - "$@" <<'ENDPY'
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


def day(ts):
    if not ts:
        return "-"
    d = time.strftime("%Y-%m-%d", time.localtime(ts))
    return "today" if d == TODAY else d


def plural(n, word):
    return "%d %s%s" % (n, word, "" if n == 1 else "s")


CWD = git_root(os.path.abspath(args[0]) if args else os.getcwd())


# -------------------------------------------------------------- measuring ---

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
    sizes = [c for c in (session_context(f) for f in files) if c]
    med = median(sizes)

    mem = os.path.join(root, ".claude", "memory")
    memo_t = memo_l = 0
    memo_p = os.path.join(mem, "PROJECT_CONTEXT.md")
    if os.path.exists(memo_p):
        text = io.open(memo_p, encoding="utf-8", errors="replace").read()
        memo_t, memo_l = max(1, len(text) // 4), len(text.splitlines())

    # One line per session start that actually received the memo. Counting what
    # happened is the only honest basis for a savings figure - a total over every
    # session ever recorded would be a hypothetical dressed up as a measurement.
    starts = []
    try:
        for line in io.open(os.path.join(mem, ".starts"), encoding="utf-8", errors="replace"):
            bits = line.split()
            if len(bits) == 2:
                starts.append((int(bits[0]), int(bits[1])))
    except Exception:
        pass

    return {
        "project": os.path.basename(root.rstrip("/\\")) or root,
        "root": root,
        "sessions": len(sizes),
        "resume_cost": med,
        "memo_tokens": memo_t,
        "memo_lines": memo_l,
        "starts": len(starts),
        "since": min([t for t, _ in starts] or [0]),
        "saved_real": sum(max(0, med - m) for _, m in starts),
        "saved_per_start": max(0, med - memo_t) if memo_t and med else 0,
        "saved_percent": round((med - memo_t) * 100.0 / med, 1) if memo_t and med else 0,
        "ratio": round(med / memo_t, 1) if memo_t and med else 0,
    }


dirs = project_dirs()

# The overall figures are always computed, whichever mode we are in: the total is
# the point of the report, not something you should have to pass a flag for.
all_rows = [measure(root, files) for root, files in dirs]

if ALL:
    rows, FALLBACK = all_rows, False
else:
    # Sessions started in a subdirectory are recorded under that path, so take
    # everything at or below the project root, not just an exact match.
    files = [f for root, fs in dirs if under(root, CWD) for f in fs]
    rows = [measure(CWD, files)]
    FALLBACK = not rows[0]["sessions"] and not rows[0]["memo_tokens"]

summary = {
    "projects":      len([r for r in all_rows if r["sessions"]]),
    "projects_memo": len([r for r in all_rows if r["memo_tokens"]]),
    "starts":        sum(r["starts"] for r in all_rows),
    "since":         min([r["since"] for r in all_rows if r["since"]] or [0]),
    "saved_real":    sum(r["saved_real"] for r in all_rows),
}

if JSON:
    print(json.dumps({"summary": summary, "projects": rows}, indent=2))
    sys.exit(0)


# --------------------------------------------------------------- printing ---

RULE = " " * 20 + "-" * 9


def row(label, value, note=""):
    print("    %-15s %9s   %s" % (label, value, note))


def block(r):
    print("  %s" % r["project"])
    print()
    row("memo", num(r["memo_tokens"]), "tokens, %s" % plural(r["memo_lines"], "line"))
    row("a resume", num(r["resume_cost"]), "tokens")
    print(RULE)
    row("saved per start", num(r["saved_per_start"]),
        "%s%% less, %sx" % (r["saved_percent"], r["ratio"]))
    print()
    if r["starts"]:
        row("starts", num(r["starts"]), "since %s" % day(r["since"]))
        row("saved so far", num(r["saved_real"]), "tokens")
    else:
        row("starts", "0", "counting from now on")
    print()


print()

if FALLBACK:
    print("  %s" % (os.path.basename(CWD.rstrip("/\\")) or CWD))
    print("    no memo and no sessions here yet")
    print()
elif ALL:
    for r in sorted([x for x in all_rows if x["ratio"]], key=lambda x: -x["saved_real"]):
        block(r)
else:
    r = rows[0]
    if r["ratio"]:
        block(r)
    else:
        print("  %s" % r["project"])
        print()
        row("memo", "-", "none written here yet")
        row("sessions", num(r["sessions"]), "recorded")
        print()

s = summary
print("  All projects")
print()
row("with a memo", num(s["projects_memo"]), "of %d" % s["projects"])
if s["starts"]:
    row("starts", num(s["starts"]), "since %s" % day(s["since"]))
else:
    row("starts", "0", "counting from now on")
print()

print("  " + "=" * 44)
print("   SAVED BY CONTEXT ENGINE  %14s" % num(s["saved_real"]))
print("  " + "=" * 44)
print()

print("  Counts session starts that actually received the memo -")
print("  nothing hypothetical. \"A resume\" is what reloading that")
print("  project's last session costs, read from the transcript's")
print("  own token counts. /clear drops the chat context and the")
print("  memo goes straight back in.")
print()
ENDPY
