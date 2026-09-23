import { execFileSync, spawn } from "child_process";
import fs from "fs";
import os from "os";
import path from "path";

const PILL_BIN = path.join(os.homedir(), ".config", "raycast-llm-translate", "bin", "llm-pill");
const PILL_PIDFILE = path.join(os.tmpdir(), "raycast-llm-translate-pill.pid");

export function pillText(t: string): string {
  const oneLine = t.replace(/\s*\n+\s*/g, "  ·  ").trim();
  return oneLine.length > 350 ? `${oneLine.slice(0, 347)}…` : oneLine;
}

function killPreviousPill() {
  try {
    const old = parseInt(fs.readFileSync(PILL_PIDFILE, "utf8").trim(), 10);
    if (Number.isFinite(old) && old > 1) {
      const comm = execFileSync("/bin/ps", ["-p", String(old), "-o", "comm="], { encoding: "utf8" }).trim();
      if (comm.endsWith("llm-pill")) process.kill(old, "SIGTERM");
    }
  } catch {
    // no previous pill (or already gone)
  }
}

/** Multi-line wrapping pill via the native overlay helper. Returns false if unavailable. */
export function showPillOverlay(text: string, seconds: number): boolean {
  try {
    if (!fs.existsSync(PILL_BIN)) return false;
    killPreviousPill();
    const child = spawn(PILL_BIN, [String(seconds)], { detached: true, stdio: ["pipe", "ignore", "ignore"] });
    if (!child.pid) return false;
    child.stdin.write(text);
    child.stdin.end();
    child.unref();
    fs.writeFileSync(PILL_PIDFILE, String(child.pid));
    return true;
  } catch {
    return false;
  }
}
