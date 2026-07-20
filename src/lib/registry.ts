import fs from "node:fs";
import path from "node:path";
import { registryPath, sessionsDir, readJson, writeJsonAtomic, ensureDirs } from "./paths.js";

export interface SessionRegistration {
  sessionId: string;
  transcriptPath: string;
  cwd: string;
  source?: string;
  startedAt: string;
  updatedAt: string;
}

export function registerSession(reg: Omit<SessionRegistration, "startedAt" | "updatedAt">): void {
  ensureDirs();
  const existing = readJson<SessionRegistration>(registryPath(reg.sessionId));
  const now = new Date().toISOString();
  writeJsonAtomic(registryPath(reg.sessionId), {
    ...reg,
    startedAt: existing?.startedAt ?? now,
    updatedAt: now,
  });
}

export function readRegistration(sessionId: string): SessionRegistration | null {
  return readJson<SessionRegistration>(registryPath(sessionId));
}

export function removeRegistration(sessionId: string): void {
  try {
    fs.unlinkSync(registryPath(sessionId));
  } catch {}
}

export function listRegistrations(): SessionRegistration[] {
  let files: string[] = [];
  try {
    files = fs.readdirSync(sessionsDir()).filter((f) => f.endsWith(".json"));
  } catch {
    return [];
  }
  const out: SessionRegistration[] = [];
  for (const f of files) {
    const reg = readJson<SessionRegistration>(path.join(sessionsDir(), f));
    if (reg?.sessionId && reg.transcriptPath) out.push(reg);
  }
  return out;
}
