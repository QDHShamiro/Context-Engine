import Database from "better-sqlite3";
import { dbPath, ensureDirs } from "./paths.js";

export interface SummaryRow {
  id: number;
  session_id: string;
  project_dir: string;
  from_line: number;
  to_line: number;
  summary: string;
  raw_tokens: number;
  summary_tokens: number;
  model: string;
  created_at: string;
}

let db: Database.Database | null = null;

export function openDb(): Database.Database {
  if (db) return db;
  ensureDirs();
  db = new Database(dbPath());
  db.pragma("journal_mode = WAL");
  db.exec(`
    CREATE TABLE IF NOT EXISTS summaries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT NOT NULL,
      project_dir TEXT NOT NULL,
      from_line INTEGER NOT NULL,
      to_line INTEGER NOT NULL,
      summary TEXT NOT NULL,
      raw_tokens INTEGER NOT NULL,
      summary_tokens INTEGER NOT NULL,
      model TEXT NOT NULL,
      created_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_summaries_session ON summaries(session_id, id);
    CREATE INDEX IF NOT EXISTS idx_summaries_project ON summaries(project_dir, id);
  `);
  return db;
}

export function lastCompressedLine(sessionId: string): number {
  const row = openDb()
    .prepare("SELECT MAX(to_line) AS m FROM summaries WHERE session_id = ?")
    .get(sessionId) as { m: number | null };
  return row?.m ?? 0;
}

export function insertSummary(row: Omit<SummaryRow, "id" | "created_at">): void {
  openDb()
    .prepare(
      `INSERT INTO summaries (session_id, project_dir, from_line, to_line, summary, raw_tokens, summary_tokens, model, created_at)
       VALUES (@session_id, @project_dir, @from_line, @to_line, @summary, @raw_tokens, @summary_tokens, @model, @created_at)`
    )
    .run({ ...row, created_at: new Date().toISOString() });
}

export function latestSummaryForSession(sessionId: string): SummaryRow | null {
  return (openDb()
    .prepare("SELECT * FROM summaries WHERE session_id = ? ORDER BY id DESC LIMIT 1")
    .get(sessionId) ?? null) as SummaryRow | null;
}

export function latestSummaryForProject(projectDir: string): SummaryRow | null {
  return (openDb()
    .prepare("SELECT * FROM summaries WHERE project_dir = ? ORDER BY id DESC LIMIT 1")
    .get(projectDir) ?? null) as SummaryRow | null;
}

export function latestSummaryAny(): SummaryRow | null {
  return (openDb().prepare("SELECT * FROM summaries ORDER BY id DESC LIMIT 1").get() ?? null) as SummaryRow | null;
}

export function sessionTotals(sessionId: string): { rawTokens: number; count: number } {
  const row = openDb()
    .prepare("SELECT COALESCE(SUM(raw_tokens),0) AS raw, COUNT(*) AS c FROM summaries WHERE session_id = ?")
    .get(sessionId) as { raw: number; c: number };
  return { rawTokens: row.raw, count: row.c };
}

export function searchSummaries(query: string, projectDir: string | null, limit: number): SummaryRow[] {
  const like = `%${query}%`;
  if (projectDir) {
    return openDb()
      .prepare(
        `SELECT * FROM summaries WHERE summary LIKE ? AND project_dir = ? ORDER BY id DESC LIMIT ?`
      )
      .all(like, projectDir, limit) as SummaryRow[];
  }
  return openDb()
    .prepare(`SELECT * FROM summaries WHERE summary LIKE ? ORDER BY id DESC LIMIT ?`)
    .all(like, limit) as SummaryRow[];
}
