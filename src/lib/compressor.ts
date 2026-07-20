import fs from "node:fs";
import Anthropic from "@anthropic-ai/sdk";
import { loadConfig, resolveApiKey, fakeCompressEnabled, type CeConfig } from "./config.js";
import { parseTranscript, estimateTokens, estimateTextTokens, type TranscriptEntry } from "./transcript.js";
import { insertSummary, lastCompressedLine, latestSummaryForSession, sessionTotals } from "./db.js";
import { readRegistration } from "./registry.js";
import { updateStatus } from "./status.js";

const MAX_CHUNK_CHARS = 300_000;

const SYSTEM_PROMPT = `You are the compression engine for a coding assistant's conversation history.
You receive an optional PREVIOUS SUMMARY plus a chunk of older conversation transcript (user messages, assistant messages, tool calls, tool results).
Produce ONE updated, self-contained summary in Markdown that merges the previous summary with the new content. The summary replaces the raw history, so it must stand alone.

Structure:
## Task & Goal
## Decisions
## Current State
## Open TODOs
## Files & Code
## Key Facts

Rules:
- Preserve exact file paths, identifiers, commands, error strings, numbers, URLs.
- Keep short code snippets only when they capture a decision or non-obvious detail.
- Drop greetings, chit-chat, redundant reasoning, superseded attempts, verbose tool output.
- Never invent information. Prefer terse bullet points.`;

export interface CompressResult {
  compressed: boolean;
  reason?: string;
  sessionId: string;
  fromLine?: number;
  toLine?: number;
  messages?: number;
  rawTokens?: number;
  summaryTokens?: number;
  savedTokens?: number;
  model?: string;
}

export async function compressSession(sessionId: string, opts: { force?: boolean } = {}): Promise<CompressResult> {
  const cfg = loadConfig();
  const reg = readRegistration(sessionId);
  if (!reg) return { compressed: false, sessionId, reason: "session not registered" };

  let raw: string;
  try {
    raw = fs.readFileSync(reg.transcriptPath, "utf8");
  } catch {
    return { compressed: false, sessionId, reason: "transcript not readable" };
  }

  const { entries } = parseTranscript(raw);
  const from = lastCompressedLine(sessionId);
  const backlog = entries.filter((e) => e.line >= from);
  const minBacklog = cfg.keepRecentMessages + (opts.force ? 1 : cfg.minCompressMessages);
  if (backlog.length < minBacklog) {
    return { compressed: false, sessionId, reason: `backlog too small (${backlog.length} messages)` };
  }

  const keep = Math.max(1, Math.min(cfg.keepRecentMessages, backlog.length - 1));
  const cut = backlog[backlog.length - keep].line;
  const target = backlog.filter((e) => e.line < cut);
  if (target.length === 0) return { compressed: false, sessionId, reason: "nothing to compress" };

  const rawTokens = estimateTokens(target.reduce((n, e) => n + e.rawChars, 0));
  const prev = latestSummaryForSession(sessionId)?.summary ?? null;

  updateStatus(sessionId, { state: "compressing" });
  let summary: string;
  let model = cfg.model;
  try {
    if (fakeCompressEnabled()) {
      summary = fakeSummary(prev, target);
      model = "fake";
    } else {
      summary = await summarize(cfg, prev, target);
    }
  } catch (err) {
    updateStatus(sessionId, { state: "error", lastError: String(err instanceof Error ? err.message : err) });
    throw err;
  }

  const summaryTokens = estimateTextTokens(summary);

  if (lastCompressedLine(sessionId) !== from) {
    updateStatus(sessionId, { state: "idle" });
    return { compressed: false, sessionId, reason: "concurrent compression won" };
  }

  insertSummary({
    session_id: sessionId,
    project_dir: reg.cwd,
    from_line: from,
    to_line: cut,
    summary,
    raw_tokens: rawTokens,
    summary_tokens: summaryTokens,
    model,
  });

  const totals = sessionTotals(sessionId);
  const saved = Math.max(0, totals.rawTokens - summaryTokens);
  updateStatus(sessionId, {
    state: "idle",
    totalRawTokens: totals.rawTokens,
    totalSavedTokens: saved,
    compressions: totals.count,
    lastCompressionAt: new Date().toISOString(),
    lastCompressionRange: `${from}-${cut}`,
    lastSavedTokens: Math.max(0, rawTokens - summaryTokens),
    lastError: undefined,
  });

  return {
    compressed: true,
    sessionId,
    fromLine: from,
    toLine: cut,
    messages: target.length,
    rawTokens,
    summaryTokens,
    savedTokens: Math.max(0, rawTokens - summaryTokens),
    model,
  };
}

async function summarize(cfg: CeConfig, prev: string | null, target: TranscriptEntry[]): Promise<string> {
  const apiKey = resolveApiKey(cfg);
  if (!apiKey) {
    throw new Error("no API key: set ANTHROPIC_API_KEY or \"apiKey\" in config.json");
  }
  const client = new Anthropic({ apiKey });

  const chunks: string[] = [];
  let current: string[] = [];
  let currentLen = 0;
  for (const e of target) {
    const text = e.rendered;
    if (currentLen + text.length > MAX_CHUNK_CHARS && current.length > 0) {
      chunks.push(current.join("\n\n"));
      current = [];
      currentLen = 0;
    }
    current.push(text);
    currentLen += text.length;
  }
  if (current.length > 0) chunks.push(current.join("\n\n"));

  let running = prev;
  for (const chunk of chunks) {
    const prompt = [
      running ? `PREVIOUS SUMMARY:\n${running}` : "PREVIOUS SUMMARY: (none)",
      `NEW TRANSCRIPT CHUNK:\n${chunk}`,
      "Return the updated merged summary now.",
    ].join("\n\n---\n\n");

    const response = await client.messages.create({
      model: cfg.model,
      max_tokens: cfg.maxSummaryTokens,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: prompt }],
    });
    running = response.content
      .filter((b): b is Anthropic.TextBlock => b.type === "text")
      .map((b) => b.text)
      .join("\n")
      .trim();
    if (!running) throw new Error("empty summary from API");
  }
  return running ?? "";
}

function fakeSummary(prev: string | null, target: TranscriptEntry[]): string {
  const bullets = target.slice(0, 40).map((e) => `- ${e.rendered.split("\n")[1]?.slice(0, 80) ?? ""}`);
  return [
    "## Task & Goal",
    prev ? "(merged with previous summary)" : "(fake summary for testing)",
    "## Key Facts",
    ...bullets,
  ].join("\n");
}
