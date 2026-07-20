import fs from "node:fs";
import { daemonPid, ensureDaemonRunning, log } from "../lib/daemon-ctl.js";
import { hookStampPath, ensureDirs } from "../lib/paths.js";

const THROTTLE_MS = 30_000;

function main(): void {
  ensureDirs();
  const stamp = hookStampPath();
  try {
    const age = Date.now() - fs.statSync(stamp).mtimeMs;
    if (age < THROTTLE_MS) return;
  } catch {}
  try {
    fs.writeFileSync(stamp, String(Date.now()));
  } catch {}

  if (!daemonPid()) {
    const pid = ensureDaemonRunning();
    log(`post-tool-use: daemon was down, respawned (pid ${pid})`);
  }
}

try {
  main();
} catch (err) {
  log(`post-tool-use hook error: ${err}`);
}
process.exit(0);
