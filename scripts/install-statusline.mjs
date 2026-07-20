import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const statuslineJs = path.join(root, "dist", "statusline.js");
if (!fs.existsSync(statuslineJs)) {
  console.error("dist/statusline.js missing — run `npm run build` first.");
  process.exit(1);
}

const settingsPath = path.join(os.homedir(), ".claude", "settings.json");
let settings = {};
try {
  settings = JSON.parse(fs.readFileSync(settingsPath, "utf8"));
} catch {}

if (settings.statusLine) {
  console.log("Previous statusLine setting (replaced):");
  console.log(JSON.stringify(settings.statusLine, null, 2));
}

settings.statusLine = {
  type: "command",
  command: `node "${statuslineJs}"`,
  padding: 0,
};

fs.mkdirSync(path.dirname(settingsPath), { recursive: true });
fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2));
console.log(`statusLine configured in ${settingsPath}:`);
console.log(`  node "${statuslineJs}"`);
console.log("Restart Claude Code to see it.");
