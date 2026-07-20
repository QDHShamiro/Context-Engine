import fs from "node:fs";
import { removeRegistration } from "../lib/registry.js";
import { log } from "../lib/daemon-ctl.js";

interface HookInput {
  session_id?: string;
  reason?: string;
}

function main(): void {
  let input: HookInput = {};
  try {
    input = JSON.parse(fs.readFileSync(0, "utf8"));
  } catch {}
  if (input.session_id) {
    removeRegistration(input.session_id);
    log(`session ${input.session_id} ended (${input.reason ?? "?"})`);
  }
}

try {
  main();
} catch (err) {
  log(`session-end hook error: ${err}`);
}
process.exit(0);
