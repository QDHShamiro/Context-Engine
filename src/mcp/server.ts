import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import {
  latestSummaryForSession,
  latestSummaryForProject,
  latestSummaryAny,
  searchSummaries,
  type SummaryRow,
} from "../lib/db.js";
import { listRegistrations } from "../lib/registry.js";
import { readStatus } from "../lib/status.js";
import { loadConfig } from "../lib/config.js";
import { daemonPid } from "../lib/daemon-ctl.js";
import { compressSession } from "../lib/compressor.js";
import { fmt } from "../lib/format.js";

const server = new McpServer({ name: "context-engine", version: "0.1.0" });

function text(t: string) {
  return { content: [{ type: "text" as const, text: t }] };
}

function pickSessionId(explicit?: string): string | null {
  if (explicit) return explicit;
  const regs = listRegistrations().sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
  const cwd = process.cwd();
  return (regs.find((r) => r.cwd === cwd) ?? regs[0])?.sessionId ?? null;
}

function pickSummary(sessionId?: string): SummaryRow | null {
  if (sessionId) return latestSummaryForSession(sessionId);
  return latestSummaryForProject(process.cwd()) ?? latestSummaryAny();
}

function describe(row: SummaryRow): string {
  return (
    `Compressed summary (session ${row.session_id}, transcript lines ${row.from_line}-${row.to_line}, ` +
    `created ${row.created_at}, ~${row.raw_tokens} raw tokens -> ~${row.summary_tokens} summary tokens):\n\n` +
    row.summary
  );
}

server.registerTool(
  "get_compressed_context",
  {
    description:
      "Get the latest compressed summary of earlier conversation history. Use this instead of re-reading long old history. Without session_id, returns the latest summary for the current project.",
    inputSchema: { session_id: z.string().optional().describe("Claude Code session id (optional)") },
  },
  async ({ session_id }) => {
    const row = pickSummary(session_id);
    if (!row) return text("No compressed summary available yet.");
    return text(describe(row));
  }
);

server.registerTool(
  "search_history",
  {
    description: "Full-text search over all compressed conversation summaries of this machine (current project first).",
    inputSchema: {
      query: z.string().describe("Search text"),
      limit: z.number().int().min(1).max(20).optional().describe("Max results (default 5)"),
    },
  },
  async ({ query, limit }) => {
    const n = limit ?? 5;
    let rows = searchSummaries(query, process.cwd(), n);
    if (rows.length < n) {
      const more = searchSummaries(query, null, n).filter((r) => !rows.some((x) => x.id === r.id));
      rows = rows.concat(more).slice(0, n);
    }
    if (rows.length === 0) return text(`No summaries matching "${query}".`);
    return text(rows.map((r) => describe(r)).join("\n\n====\n\n"));
  }
);

server.registerTool(
  "force_compress",
  {
    description:
      "Trigger a Context Engine compression now, regardless of thresholds. Without session_id, targets the most recently active session of the current project.",
    inputSchema: { session_id: z.string().optional().describe("Claude Code session id (optional)") },
  },
  async ({ session_id }) => {
    const sid = pickSessionId(session_id);
    if (!sid) return text("No registered session found (is the plugin's SessionStart hook active?).");
    try {
      const result = await compressSession(sid, { force: true });
      if (!result.compressed) return text(`Compression skipped for ${sid}: ${result.reason}`);
      return text(
        `Compressed session ${sid}: transcript lines ${result.fromLine}-${result.toLine}, ` +
          `${result.messages} messages, ~${result.rawTokens} -> ~${result.summaryTokens} tokens ` +
          `(saved ~${result.savedTokens}, model ${result.model}).`
      );
    } catch (err) {
      return text(`Compression failed for ${sid}: ${err instanceof Error ? err.message : err}`);
    }
  }
);

server.registerTool(
  "get_status",
  {
    description: "Status of the Context Engine: active sessions, token counts, backlog, compressions, daemon state, config.",
    inputSchema: {},
  },
  async () => {
    const cfg = loadConfig();
    const pid = daemonPid();
    const regs = listRegistrations().sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
    const lines: string[] = [];
    lines.push(`daemon: ${pid ? `running (pid ${pid})` : "NOT RUNNING"}`);
    lines.push(
      `config: tokenThreshold=${cfg.tokenThreshold}, messageThreshold=${cfg.messageThreshold}, ` +
        `keepRecentMessages=${cfg.keepRecentMessages}, model=${cfg.model}`
    );
    if (regs.length === 0) lines.push("sessions: none registered");
    for (const reg of regs) {
      const s = readStatus(reg.sessionId);
      if (!s) {
        lines.push(`- ${reg.sessionId} (${reg.cwd}): no status yet`);
        continue;
      }
      lines.push(
        `- ${reg.sessionId} (${reg.cwd}): state=${s.state}, context~${s.contextTokens} tokens, ` +
          `backlog ${s.backlogMessages} msgs/~${s.backlogTokens} tokens, ` +
          `compressions=${s.compressions}, totalSaved~${s.totalSavedTokens} tokens` +
          (s.lastCompressionAt ? `, last=${s.lastCompressionAt}` : "") +
          (s.lastError ? `, lastError=${s.lastError}` : "")
      );
    }
    return text(lines.join("\n"));
  }
);

server.registerTool(
  "get_savings",
  {
    description:
      "Show how much of the conversation has already been compressed: compression rate (percent) plus raw token counts. Without session_id, targets the most recently active session of the current project.",
    inputSchema: { session_id: z.string().optional().describe("Claude Code session id (optional)") },
  },
  async ({ session_id }) => {
    const sid = pickSessionId(session_id);
    if (!sid) return text("No registered session found (is the plugin's SessionStart hook active?).");
    const s = readStatus(sid);
    if (!s) return text(`Session ${sid}: no status yet (daemon may not have polled it).`);

    const backlogLine = `Backlog:      ${fmt(s.backlogTokens)} tokens (${s.backlogMessages} msgs, not yet compressed)`;
    if (s.compressions === 0 || s.totalRawTokens <= 0) {
      return text(
        `Session ${sid}\n` +
          `Compressed:   nothing yet\n` +
          `${backlogLine}\n` +
          `Context now:  ${fmt(s.contextTokens)} tokens`
      );
    }

    const savedPct = Math.round((s.totalSavedTokens / s.totalRawTokens) * 100);
    const compressedTo = Math.max(0, s.totalRawTokens - s.totalSavedTokens);
    return text(
      `Session ${sid}\n` +
        `Compressed:   ${fmt(s.totalRawTokens)} → ${fmt(compressedTo)} tokens\n` +
        `Saved:        ${fmt(s.totalSavedTokens)} tokens (${savedPct}%)\n` +
        `Compressions: ${s.compressions}\n` +
        `${backlogLine}\n` +
        `Context now:  ${fmt(s.contextTokens)} tokens` +
        (s.lastCompressionAt ? `\nLast:         ${s.lastCompressionAt}` : "")
    );
  }
);

await server.connect(new StdioServerTransport());
