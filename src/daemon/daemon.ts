import fs from "node:fs";
import { loadConfig } from "../lib/config.js";
import { parseTranscript, estimateTokens, type TranscriptEntry } from "../lib/transcript.js";
import { lastCompressedLine } from "../lib/db.js";
import { listRegistrations, removeRegistration, type SessionRegistration } from "../lib/registry.js";
import { updateStatus } from "../lib/status.js";
import { compressSession } from "../lib/compressor.js";
import { acquireLock, releaseLock, log } from "../lib/daemon-ctl.js";
import { ensureDirs, sessionsDir } from "../lib/paths.js";

interface Tracked {
  reg: SessionRegistration;
  size: number;
  entries: TranscriptEntry[];
  contextTokens: number;
  inFlight: boolean;
  retryAt: number;
  lastActivity: number;
}

const once = process.argv.includes("--once");
const sessions = new Map<string, Tracked>();
let lastGlobalActivity = Date.now();

function loadSession(reg: SessionRegistration): Tracked {
  let raw = "";
  let size = 0;
  try {
    raw = fs.readFileSync(reg.transcriptPath, "utf8");
    size = fs.statSync(reg.transcriptPath).size;
  } catch {}
  const parsed = parseTranscript(raw);
  return {
    reg,
    size,
    entries: parsed.entries,
    contextTokens: parsed.contextTokens,
    inFlight: false,
    retryAt: 0,
    lastActivity: Date.now(),
  };
}

function refreshRegistrations(): void {
  const regs = listRegistrations();
  const seen = new Set<string>();
  for (const reg of regs) {
    seen.add(reg.sessionId);
    const existing = sessions.get(reg.sessionId);
    if (!existing) {
      log(`tracking session ${reg.sessionId} (${reg.transcriptPath})`);
      sessions.set(reg.sessionId, loadSession(reg));
      lastGlobalActivity = Date.now();
    } else {
      existing.reg = reg;
    }
  }
  for (const id of sessions.keys()) {
    if (!seen.has(id)) {
      log(`dropping session ${id} (unregistered)`);
      sessions.delete(id);
    }
  }
}

function pollSession(t: Tracked): void {
  let size = 0;
  try {
    size = fs.statSync(t.reg.transcriptPath).size;
  } catch {
    return;
  }
  if (size === t.size) return;
  lastGlobalActivity = Date.now();
  t.lastActivity = Date.now();
  if (size < t.size) {
    const fresh = loadSession(t.reg);
    t.size = fresh.size;
    t.entries = fresh.entries;
    t.contextTokens = fresh.contextTokens;
  } else {
    const fresh = loadSession(t.reg);
    t.size = fresh.size;
    t.entries = fresh.entries;
    if (fresh.contextTokens) t.contextTokens = fresh.contextTokens;
  }
  publishStatus(t);
}

function backlogOf(t: Tracked): { messages: number; tokens: number } {
  const from = lastCompressedLine(t.reg.sessionId);
  const backlog = t.entries.filter((e) => e.line >= from);
  const tokens = estimateTokens(backlog.reduce((n, e) => n + e.rawChars, 0));
  return { messages: backlog.length, tokens };
}

function publishStatus(t: Tracked): void {
  const backlog = backlogOf(t);
  updateStatus(t.reg.sessionId, {
    contextTokens: t.contextTokens,
    backlogTokens: backlog.tokens,
    backlogMessages: backlog.messages,
    daemonPid: process.pid,
  });
}

async function maybeCompress(t: Tracked): Promise<void> {
  if (t.inFlight || Date.now() < t.retryAt) return;
  const cfg = loadConfig();
  const backlog = backlogOf(t);
  const overTokens = backlog.tokens >= cfg.tokenThreshold;
  const overMessages = backlog.messages >= cfg.messageThreshold + cfg.keepRecentMessages;
  const enough = backlog.messages >= cfg.keepRecentMessages + cfg.minCompressMessages;
  if (!enough || (!overTokens && !overMessages)) return;

  t.inFlight = true;
  log(
    `compressing ${t.reg.sessionId}: backlog ${backlog.messages} msgs / ~${backlog.tokens} tokens ` +
      `(thresholds: ${cfg.tokenThreshold} tokens, ${cfg.messageThreshold} msgs)`
  );
  try {
    const result = await compressSession(t.reg.sessionId);
    if (result.compressed) {
      log(
        `compressed ${t.reg.sessionId}: lines ${result.fromLine}-${result.toLine}, ` +
          `${result.messages} msgs, ~${result.rawTokens} -> ~${result.summaryTokens} tokens (saved ~${result.savedTokens})`
      );
    } else {
      log(`compression skipped for ${t.reg.sessionId}: ${result.reason}`);
    }
    publishStatus(t);
  } catch (err) {
    const cfgNow = loadConfig();
    t.retryAt = Date.now() + cfgNow.failureCooldownMinutes * 60_000;
    log(`compression FAILED for ${t.reg.sessionId}: ${err instanceof Error ? err.message : err}`);
  } finally {
    t.inFlight = false;
  }
}

async function tick(): Promise<void> {
  refreshRegistrations();
  for (const t of sessions.values()) {
    pollSession(t);
    await maybeCompress(t);
  }
}

async function main(): Promise<void> {
  ensureDirs();
  if (once) {
    refreshRegistrations();
    for (const t of sessions.values()) {
      pollSession(t);
      publishStatus(t);
      await maybeCompress(t);
    }
    return;
  }

  if (!acquireLock()) {
    log("daemon already running, exiting");
    return;
  }
  log(`daemon started (pid ${process.pid})`);

  const shutdown = () => {
    log("daemon shutting down");
    releaseLock();
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);

  try {
    fs.watch(sessionsDir(), () => void tick().catch((e) => log(`tick error: ${e}`)));
  } catch {}

  const cfg = loadConfig();
  const interval = setInterval(() => {
    void tick().catch((e) => log(`tick error: ${e}`));
    const idleMs = loadConfig().idleExitMinutes * 60_000;
    if (Date.now() - lastGlobalActivity > idleMs && sessions.size === 0) {
      log("idle with no sessions, exiting");
      clearInterval(interval);
      releaseLock();
      process.exit(0);
    }
  }, 2000);

  if (cfg.debug) log("debug mode on");
}

main().catch((err) => {
  log(`daemon fatal: ${err instanceof Error ? (err.stack ?? err.message) : err}`);
  releaseLock();
  process.exit(1);
});
