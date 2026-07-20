import fs from "node:fs";
import path from "node:path";
import { readStatus } from "./lib/status.js";
import { fmt } from "./lib/format.js";

interface StdinData {
  session_id?: string;
  model?: { display_name?: string };
  workspace?: { current_dir?: string };
  context_window?: {
    total_input_tokens?: number | null;
    used_percentage?: number | null;
  };
}

const DIM = "\x1b[2m";
const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";
const RED = "\x1b[31m";
const RESET = "\x1b[0m";

function ago(iso: string): string {
  const s = Math.max(0, Math.floor((Date.now() - Date.parse(iso)) / 1000));
  if (s < 60) return `${s}s ago`;
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  return `${Math.floor(s / 3600)}h ago`;
}

function main(): void {
  let data: StdinData = {};
  try {
    data = JSON.parse(fs.readFileSync(0, "utf8"));
  } catch {}

  const parts: string[] = [];
  const model = data.model?.display_name;
  const dir = data.workspace?.current_dir ? path.basename(data.workspace.current_dir) : null;
  if (model) parts.push(model);
  if (dir) parts.push(dir);

  const ctx = data.context_window;
  if (ctx?.total_input_tokens) {
    const pct = typeof ctx.used_percentage === "number" ? ` ${Math.round(ctx.used_percentage)}%` : "";
    parts.push(`ctx ${fmt(ctx.total_input_tokens)}${pct}`);
  }

  const status = data.session_id ? readStatus(data.session_id) : null;
  if (!status) {
    parts.push(`${DIM}CE starting…${RESET}`);
  } else if (status.state === "compressing") {
    parts.push(`${YELLOW}CE compressing…${RESET}`);
  } else if (status.state === "error") {
    parts.push(`${RED}CE error: ${(status.lastError ?? "").slice(0, 40)}${RESET}`);
  } else {
    const bits: string[] = [];
    bits.push(`backlog ${fmt(status.backlogTokens)}`);
    if (status.compressions > 0 && status.lastCompressionAt) {
      bits.push(`${GREEN}✓${RESET} ${ago(status.lastCompressionAt)}`);
      bits.push(`saved ${fmt(status.totalSavedTokens)}`);
    }
    parts.push(`CE ${bits.join(" · ")}`);
  }

  process.stdout.write(parts.join(`${DIM} | ${RESET}`));
}

main();
