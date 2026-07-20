import { configPath, readJson } from "./paths.js";

export interface CeConfig {
  tokenThreshold: number;
  messageThreshold: number;
  keepRecentMessages: number;
  minCompressMessages: number;
  model: string;
  maxSummaryTokens: number;
  apiKey: string | null;
  failureCooldownMinutes: number;
  idleExitMinutes: number;
  debug: boolean;
}

export const DEFAULT_CONFIG: CeConfig = {
  tokenThreshold: 50000,
  messageThreshold: 30,
  keepRecentMessages: 10,
  minCompressMessages: 8,
  model: "claude-haiku-4-5",
  maxSummaryTokens: 2500,
  apiKey: null,
  failureCooldownMinutes: 5,
  idleExitMinutes: 45,
  debug: false,
};

export function loadConfig(): CeConfig {
  const fileCfg = readJson<Partial<CeConfig>>(configPath()) ?? {};
  return { ...DEFAULT_CONFIG, ...fileCfg };
}

export function resolveApiKey(cfg: CeConfig): string | null {
  return cfg.apiKey ?? process.env.ANTHROPIC_API_KEY ?? null;
}

export function fakeCompressEnabled(): boolean {
  return process.env.CE_FAKE_COMPRESS === "1";
}
