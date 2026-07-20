import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { lockPath, logPath, ensureDirs, readJson } from "./paths.js";

interface LockFile {
  pid: number;
  startedAt: string;
}

export function pidAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (err: any) {
    return err?.code === "EPERM";
  }
}

export function daemonPid(): number | null {
  const lock = readJson<LockFile>(lockPath());
  if (lock?.pid && pidAlive(lock.pid)) return lock.pid;
  return null;
}

export function acquireLock(): boolean {
  ensureDirs();
  const payload = JSON.stringify({ pid: process.pid, startedAt: new Date().toISOString() });
  try {
    fs.writeFileSync(lockPath(), payload, { flag: "wx" });
    return true;
  } catch {
    const lock = readJson<LockFile>(lockPath());
    if (lock?.pid && pidAlive(lock.pid) && lock.pid !== process.pid) return false;
    try {
      fs.writeFileSync(lockPath(), payload);
      return true;
    } catch {
      return false;
    }
  }
}

export function releaseLock(): void {
  const lock = readJson<LockFile>(lockPath());
  if (lock?.pid === process.pid) {
    try {
      fs.unlinkSync(lockPath());
    } catch {}
  }
}

export function ensureDaemonRunning(): number | null {
  if (daemonPid()) return daemonPid();
  ensureDirs();
  const here = path.dirname(fileURLToPath(import.meta.url));
  const daemonJs = path.resolve(here, "..", "daemon", "daemon.js");
  if (!fs.existsSync(daemonJs)) return null;
  try {
    const child = spawn(process.execPath, [daemonJs], {
      detached: true,
      stdio: "ignore",
      windowsHide: true,
      env: process.env,
    });
    child.unref();
    return child.pid ?? null;
  } catch {
    return null;
  }
}

export function log(message: string): void {
  try {
    ensureDirs();
    fs.appendFileSync(logPath(), `[${new Date().toISOString()}] ${message}\n`);
  } catch {}
}
