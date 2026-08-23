import { Clipboard, Toast, getPreferenceValues, showToast } from "@raycast/api";
import { execFileSync, spawn } from "child_process";
import fs from "fs";
import os from "os";
import path from "path";
import {
  CONFIG_PATH,
  DEFAULT_MODEL,
  OPENROUTER_URL,
  Preferences,
  getInputText,
  openRouterHeaders,
  resolveApiKey,
  systemPrompt,
} from "./translate-core";

interface ChatCompletion {
  choices?: { message?: { content?: string } }[];
}

const PILL_BIN = path.join(os.homedir(), ".config", "raycast-llm-translate", "bin", "llm-pill");
const PILL_PIDFILE = path.join(os.tmpdir(), "raycast-llm-translate-pill.pid");

function pillText(t: string): string {
  const oneLine = t.replace(/\s*\n+\s*/g, "  ·  ").trim();
  return oneLine.length > 350 ? `${oneLine.slice(0, 347)}…` : oneLine;
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

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
function showPillOverlay(text: string, seconds: number): boolean {
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

export default async function TranslateSelectionQuick() {
  // Immediate feedback FIRST — before the (slow) selected-text grab, so the pill
  // area reacts the moment the hotkey is pressed.
  const toast = await showToast({ style: Toast.Style.Animated, title: "Translating…" });
  const fail = async (title: string, message?: string, holdMs = 5000) => {
    toast.style = Toast.Style.Failure;
    toast.title = title;
    if (message) toast.message = message;
    await sleep(holdMs);
    await toast.hide();
  };

  const prefs = getPreferenceValues<Preferences>();
  const primary = prefs.primaryLanguage?.trim() || "German";
  const secondary = prefs.secondaryLanguage?.trim() || "English";
  const model = prefs.model || DEFAULT_MODEL;
  const pillSeconds = parseInt(prefs.pillDuration ?? "6", 10) || 6;

  const apiKey = resolveApiKey(prefs.apiKey);
  if (!apiKey) {
    await fail("No OpenRouter API key", `Set it in the extension preferences or ${CONFIG_PATH}`);
    return;
  }

  const input = await getInputText();
  if (!input) {
    await fail("No text selected", "And the clipboard is empty");
    return;
  }

  try {
    const resp = await fetch(OPENROUTER_URL, {
      method: "POST",
      signal: AbortSignal.timeout(45000),
      headers: openRouterHeaders(apiKey),
      body: JSON.stringify({
        model,
        temperature: 0.2,
        messages: [
          { role: "system", content: systemPrompt(primary, secondary) },
          { role: "user", content: input.text },
        ],
      }),
    });
    if (!resp.ok) {
      const bodyText = await resp.text().catch(() => "");
      throw new Error(`OpenRouter ${resp.status}: ${bodyText.slice(0, 200)}`);
    }
    const data = (await resp.json()) as ChatCompletion;
    const translation = data.choices?.[0]?.message?.content?.trim() ?? "";
    if (!translation) throw new Error("The model returned an empty translation.");

    if (prefs.copyQuickResult) await Clipboard.copy(translation);

    if (showPillOverlay(translation, pillSeconds)) {
      await toast.hide();
    } else {
      // fallback: Raycast toast is single-line, held open for the configured duration
      toast.style = Toast.Style.Success;
      toast.title = pillText(translation);
      await sleep(pillSeconds * 1000);
      await toast.hide();
    }
  } catch (e) {
    const err = e as Error;
    const msg = err.name === "TimeoutError" || err.name === "AbortError" ? "Timed out after 45 s" : err.message;
    await fail("Translation failed", msg, 6000);
  }
}
