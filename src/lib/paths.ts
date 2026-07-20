import os from "node:os";
import path from "node:path";
import fs from "node:fs";

export function dataDir(): string {
  return process.env.CE_DATA_DIR ?? path.join(os.homedir(), ".claude", "context-engine");
}

export function sessionsDir(): string {
  return path.join(dataDir(), "sessions");
}

export function statusDir(): string {
  return path.join(dataDir(), "status");
}

export function dbPath(): string {
  return path.join(dataDir(), "context-engine.db");
}

export function configPath(): string {
  return path.join(dataDir(), "config.json");
}

export function lockPath(): string {
  return path.join(dataDir(), "daemon.lock");
}

export function logPath(): string {
  return path.join(dataDir(), "daemon.log");
}

export function hookStampPath(): string {
  return path.join(dataDir(), "hookcheck.stamp");
}

export function ensureDirs(): void {
  for (const d of [dataDir(), sessionsDir(), statusDir()]) {
    fs.mkdirSync(d, { recursive: true });
  }
}

export function registryPath(sessionId: string): string {
  return path.join(sessionsDir(), `${safeName(sessionId)}.json`);
}

export function statusPath(sessionId: string): string {
  return path.join(statusDir(), `${safeName(sessionId)}.json`);
}

function safeName(id: string): string {
  return id.replace(/[^a-zA-Z0-9_-]/g, "-");
}

export function writeJsonAtomic(file: string, value: unknown): void {
  const tmp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(value, null, 2));
  fs.renameSync(tmp, file);
}

export function readJson<T>(file: string): T | null {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8")) as T;
  } catch {
    return null;
  }
}
