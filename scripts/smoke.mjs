import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), "ce-smoke-"));
const transcriptPath = path.join(dataDir, "transcript.jsonl");
const sessionId = "smoke-session";

process.env.CE_DATA_DIR = dataDir;
process.env.CE_FAKE_COMPRESS = "1";
const childEnv = { ...process.env };

let passed = 0;
let failed = 0;
function check(name, cond, extra = "") {
  if (cond) {
    passed++;
    console.log(`PASS ${name}`);
  } else {
    failed++;
    console.log(`FAIL ${name}${extra ? ` — ${extra}` : ""}`);
  }
}

function entry(role, textContent, i) {
  const base = {
    type: role,
    uuid: `u-${role}-${i}`,
    timestamp: new Date().toISOString(),
    sessionId,
    isSidechain: false,
    message: { role, content: [{ type: "text", text: textContent }] },
  };
  if (role === "assistant") {
    base.message.usage = {
      input_tokens: 100 + i,
      cache_read_input_tokens: 2000,
      cache_creation_input_tokens: 50,
      output_tokens: 80,
    };
  }
  return JSON.stringify(base);
}

function appendMessages(count, offset) {
  const lines = [];
  for (let i = 0; i < count; i++) {
    const n = offset + i;
    lines.push(entry("user", `User message ${n}: please fix bug in src/File${n}.ts, threshold is ${n * 10}. ${"x".repeat(300)}`, n));
    lines.push(entry("assistant", `Assistant reply ${n}: changed src/File${n}.ts line ${n}. ${"y".repeat(300)}`, n));
  }
  fs.appendFileSync(transcriptPath, lines.join("\n") + "\n");
}

fs.mkdirSync(dataDir, { recursive: true });
fs.writeFileSync(
  path.join(dataDir, "config.json"),
  JSON.stringify({ tokenThreshold: 500, messageThreshold: 10, keepRecentMessages: 4, minCompressMessages: 2 })
);

appendMessages(20, 0);

const { registerSession } = await import(pathToUrl("dist/lib/registry.js"));
registerSession({ sessionId, transcriptPath, cwd: root, source: "smoke" });

function pathToUrl(rel) {
  return new URL(`file:///${path.join(root, rel).replace(/\\/g, "/")}`).href;
}

function runOnce() {
  const r = spawnSync(process.execPath, [path.join(root, "dist", "daemon", "daemon.js"), "--once"], {
    env: childEnv,
    encoding: "utf8",
  });
  if (r.status !== 0) console.log("daemon --once stderr:", r.stderr);
  return r.status;
}

check("daemon --once exits 0", runOnce() === 0);

const db = await import(pathToUrl("dist/lib/db.js"));
const statusMod = await import(pathToUrl("dist/lib/status.js"));

const row1 = db.latestSummaryForSession(sessionId);
check("summary row created", !!row1, "no row in DB");
check("summary has content", !!row1 && row1.summary.length > 20);
check("summary raw_tokens > 0", !!row1 && row1.raw_tokens > 0);

const status1 = statusMod.readStatus(sessionId);
check("status file written", !!status1);
check("status savedTokens > 0", !!status1 && status1.totalSavedTokens > 0, JSON.stringify(status1));
check("status state idle", !!status1 && status1.state === "idle");
check("context tokens from usage", !!status1 && status1.contextTokens > 2000, `got ${status1?.contextTokens}`);

appendMessages(15, 100);
check("daemon --once (round 2) exits 0", runOnce() === 0);
const row2 = db.latestSummaryForSession(sessionId);
check("second compression happened", !!row2 && !!row1 && row2.id !== row1.id, "no new row");
check("rolling range continues", !!row2 && !!row1 && row2.from_line === row1.to_line, `from=${row2?.from_line} prevTo=${row1?.to_line}`);

const hits = db.searchSummaries("File", null, 5);
check("search finds summaries", hits.length > 0);

const { compressSession } = await import(pathToUrl("dist/lib/compressor.js"));
const skip = await compressSession("does-not-exist");
check("unknown session skipped gracefully", skip.compressed === false);

const sl = spawnSync(process.execPath, [path.join(root, "dist", "statusline.js")], {
  env: childEnv,
  encoding: "utf8",
  input: JSON.stringify({
    session_id: sessionId,
    model: { display_name: "Fable 5" },
    workspace: { current_dir: root },
    context_window: { total_input_tokens: 62345, used_percentage: 31 },
  }),
});
check("statusline exits 0", sl.status === 0, sl.stderr);
check("statusline shows model+ctx", sl.stdout.includes("Fable 5") && sl.stdout.includes("62.3k"), sl.stdout);
check("statusline shows saved tokens", sl.stdout.includes("saved"), sl.stdout);

try {
  fs.rmSync(dataDir, { recursive: true, force: true });
} catch {}

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
