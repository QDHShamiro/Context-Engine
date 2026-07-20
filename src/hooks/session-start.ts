import fs from "node:fs";
import { registerSession } from "../lib/registry.js";
import { ensureDaemonRunning, log } from "../lib/daemon-ctl.js";
import { latestSummaryForSession } from "../lib/db.js";
import { ensureDirs } from "../lib/paths.js";

interface HookInput {
  session_id?: string;
  transcript_path?: string;
  cwd?: string;
  source?: string;
}

function main(): void {
  let input: HookInput = {};
  try {
    input = JSON.parse(fs.readFileSync(0, "utf8"));
  } catch {}

  ensureDirs();
  if (input.session_id && input.transcript_path) {
    registerSession({
      sessionId: input.session_id,
      transcriptPath: input.transcript_path,
      cwd: input.cwd ?? process.cwd(),
      source: input.source,
    });
  }
  ensureDaemonRunning();

  let additionalContext: string | undefined;
  if (input.source === "resume" && input.session_id) {
    try {
      const row = latestSummaryForSession(input.session_id);
      if (row) {
        additionalContext =
          `Context Engine: compressed summary of the earlier part of this session ` +
          `(covers transcript lines ${row.from_line}-${row.to_line}, created ${row.created_at}). ` +
          `Use it instead of re-reading old history. Full text also available via the ` +
          `get_compressed_context MCP tool.\n\n${row.summary.slice(0, 8000)}`;
      }
    } catch (err) {
      log(`session-start summary lookup failed: ${err}`);
    }
  }

  const output: Record<string, unknown> = { suppressOutput: true };
  if (additionalContext) {
    output.hookSpecificOutput = { hookEventName: "SessionStart", additionalContext };
  }
  process.stdout.write(JSON.stringify(output));
}

try {
  main();
} catch (err) {
  log(`session-start hook error: ${err}`);
}
process.exit(0);
