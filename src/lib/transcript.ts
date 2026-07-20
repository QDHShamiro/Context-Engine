export interface TranscriptEntry {
  line: number;
  role: "user" | "assistant";
  rendered: string;
  rawChars: number;
  timestamp?: string;
  contextTokens?: number;
}

export interface ParseResult {
  entries: TranscriptEntry[];
  totalLines: number;
  contextTokens: number;
}

export function estimateTokens(chars: number): number {
  return Math.ceil(chars / 4);
}

export function estimateTextTokens(text: string): number {
  return estimateTokens(text.length);
}

export function parseTranscript(jsonl: string): ParseResult {
  const lines = jsonl.split("\n");
  const entries: TranscriptEntry[] = [];
  let contextTokens = 0;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line) continue;
    let obj: any;
    try {
      obj = JSON.parse(line);
    } catch {
      continue;
    }
    const entry = toEntry(obj, i);
    if (!entry) continue;
    if (entry.contextTokens) contextTokens = entry.contextTokens;
    entries.push(entry);
  }
  return { entries, totalLines: lines.length, contextTokens };
}

function toEntry(obj: any, line: number): TranscriptEntry | null {
  if (obj?.isSidechain === true || obj?.isMeta === true) return null;
  if (obj?.type !== "user" && obj?.type !== "assistant") return null;
  const msg = obj.message;
  if (!msg) return null;

  const parts: string[] = [];
  let rawChars = 0;
  const content = msg.content;

  if (typeof content === "string") {
    rawChars += content.length;
    parts.push(content);
  } else if (Array.isArray(content)) {
    for (const block of content) {
      if (!block || typeof block !== "object") continue;
      if (block.type === "text" && typeof block.text === "string") {
        rawChars += block.text.length;
        parts.push(block.text);
      } else if (block.type === "tool_use") {
        const input = safeStringify(block.input);
        rawChars += input.length;
        parts.push(`[tool call] ${block.name ?? "?"}: ${truncate(input, 400)}`);
      } else if (block.type === "tool_result") {
        const text = toolResultText(block.content);
        rawChars += text.length;
        const flag = block.is_error ? " (error)" : "";
        parts.push(`[tool result${flag}] ${truncate(text, 700)}`);
      }
    }
  }

  if (parts.length === 0) return null;

  const role = obj.type as "user" | "assistant";
  const label = obj.isCompactSummary ? "COMPACT SUMMARY" : role.toUpperCase();
  const body = parts.map((p) => truncate(p, 3000)).join("\n");

  let contextTokens: number | undefined;
  const usage = msg.usage;
  if (role === "assistant" && usage && typeof usage.input_tokens === "number") {
    contextTokens =
      (usage.input_tokens ?? 0) +
      (usage.cache_read_input_tokens ?? 0) +
      (usage.cache_creation_input_tokens ?? 0) +
      (usage.output_tokens ?? 0);
  }

  return {
    line,
    role,
    rendered: `${label}:\n${body}`,
    rawChars,
    timestamp: typeof obj.timestamp === "string" ? obj.timestamp : undefined,
    contextTokens,
  };
}

function toolResultText(content: any): string {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content
      .filter((b) => b?.type === "text" && typeof b.text === "string")
      .map((b) => b.text)
      .join("\n");
  }
  return "";
}

function safeStringify(value: unknown): string {
  try {
    return JSON.stringify(value) ?? "";
  } catch {
    return "";
  }
}

function truncate(text: string, max: number): string {
  if (text.length <= max) return text;
  const head = Math.floor(max * 0.75);
  const tail = max - head;
  return `${text.slice(0, head)}\n[… ${text.length - max} chars omitted …]\n${text.slice(-tail)}`;
}
