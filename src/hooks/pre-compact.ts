import fs from "node:fs";
import { updateStatus } from "../lib/status.js";
import { log } from "../lib/daemon-ctl.js";

interface HookInput {
  session_id?: string;
  trigger?: string;
}

function main(): void {
  let input: HookInput = {};
  try {
    input = JSON.parse(fs.readFileSync(0, "utf8"));
  } catch {}
  if (input.session_id) {
    updateStatus(input.session_id, { nativeCompactAt: new Date().toISOString() });
    log(`native compact (${input.trigger ?? "?"}) on session ${input.session_id}`);
  }
}

try {
  main();
} catch (err) {
  log(`pre-compact hook error: ${err}`);
}
process.exit(0);
