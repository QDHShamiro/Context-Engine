import { statusPath, readJson, writeJsonAtomic, ensureDirs } from "./paths.js";

export interface SessionStatus {
  sessionId: string;
  state: "idle" | "compressing" | "error";
  contextTokens: number;
  backlogTokens: number;
  backlogMessages: number;
  totalRawTokens: number;
  totalSavedTokens: number;
  compressions: number;
  lastCompressionAt?: string;
  lastCompressionRange?: string;
  lastSavedTokens?: number;
  lastError?: string;
  nativeCompactAt?: string;
  daemonPid?: number;
  updatedAt: string;
}

export function readStatus(sessionId: string): SessionStatus | null {
  return readJson<SessionStatus>(statusPath(sessionId));
}

export function updateStatus(sessionId: string, patch: Partial<SessionStatus>): SessionStatus {
  ensureDirs();
  const base: SessionStatus = readStatus(sessionId) ?? {
    sessionId,
    state: "idle",
    contextTokens: 0,
    backlogTokens: 0,
    backlogMessages: 0,
    totalRawTokens: 0,
    totalSavedTokens: 0,
    compressions: 0,
    updatedAt: new Date().toISOString(),
  };
  const next = { ...base, ...patch, sessionId, updatedAt: new Date().toISOString() };
  writeJsonAtomic(statusPath(sessionId), next);
  return next;
}
