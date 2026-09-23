import { execFileSync, spawn } from "child_process";
import fs from "fs";
import os from "os";
import path from "path";

const INPUT_BIN = path.join(os.homedir(), ".config", "raycast-llm-translate", "bin", "llm-input");
const INPUT_PIDFILE = path.join(os.tmpdir(), "raycast-llm-translate-input.pid");

export function inputBoxAvailable(): boolean {
  return fs.existsSync(INPUT_BIN);
}

function killPreviousInput() {
  try {
    const old = parseInt(fs.readFileSync(INPUT_PIDFILE, "utf8").trim(), 10);
    if (Number.isFinite(old) && old > 1) {
      const comm = execFileSync("/bin/ps", ["-p", String(old), "-o", "comm="], { encoding: "utf8" }).trim();
      if (comm.endsWith("llm-input")) process.kill(old, "SIGTERM");
    }
  } catch {
    // no previous input box (or already gone)
  }
}

/** Shows the native input prompt and resolves with the typed text on Return, or undefined if
 *  the binary is missing, the user pressed Escape, clicked away, or left it empty. */
export function showInputBox(placeholder: string): Promise<string | undefined> {
  return new Promise((resolve) => {
    if (!fs.existsSync(INPUT_BIN)) {
      resolve(undefined);
      return;
    }
    killPreviousInput();
    const child = spawn(INPUT_BIN, [placeholder], { stdio: ["ignore", "pipe", "ignore"] });
    if (child.pid) fs.writeFileSync(INPUT_PIDFILE, String(child.pid));

    let out = "";
    child.stdout.on("data", (chunk: Buffer) => {
      out += chunk.toString("utf8");
    });
    child.on("close", (code) => {
      const text = out.trim();
      resolve(code === 0 && text.length > 0 ? text : undefined);
    });
    child.on("error", () => resolve(undefined));
  });
}
