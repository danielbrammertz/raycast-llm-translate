import { Clipboard, getSelectedText } from "@raycast/api";
import fs from "fs";
import os from "os";
import path from "path";

export interface Preferences {
  primaryLanguage: string;
  secondaryLanguage: string;
  model: string;
  apiKey?: string;
  copyQuickResult?: boolean;
}

export const CONFIG_PATH = path.join(os.homedir(), ".config", "raycast-llm-translate", "config.json");

export const DEFAULT_MODEL = "google/gemini-2.5-flash-lite";

export function resolveApiKey(prefKey: string | undefined): string | undefined {
  if (prefKey && prefKey.trim().length > 0) return prefKey.trim();
  try {
    const cfg = JSON.parse(fs.readFileSync(CONFIG_PATH, "utf8")) as { apiKey?: string };
    if (cfg.apiKey && cfg.apiKey.trim().length > 0) return cfg.apiKey.trim();
  } catch {
    // missing/unreadable config file — reported by caller
  }
  return undefined;
}

export async function getInputText(): Promise<{ text: string; source: "selection" | "clipboard" } | undefined> {
  try {
    const sel = await getSelectedText();
    if (sel && sel.trim().length > 0) return { text: sel, source: "selection" };
  } catch {
    // no selection in the frontmost app — fall back to clipboard
  }
  try {
    const clip = await Clipboard.readText();
    if (clip && clip.trim().length > 0) return { text: clip, source: "clipboard" };
  } catch {
    // ignore
  }
  return undefined;
}

export function systemPrompt(primary: string, secondary: string, forcedTarget?: string): string {
  const instruction = forcedTarget
    ? `Translate the user's text into ${forcedTarget}.`
    : `Detect the language of the user's text. If the text is mainly ${primary}, translate it into ${secondary}; otherwise translate it into ${primary}.`;
  return (
    `You are a translation engine. ${instruction} ` +
    `Preserve meaning, tone, formatting, line breaks, markdown and emoji. ` +
    `Output ONLY the translation — no quotes, no explanations, no language labels.`
  );
}

export const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

export function openRouterHeaders(apiKey: string): Record<string, string> {
  return {
    Authorization: `Bearer ${apiKey}`,
    "Content-Type": "application/json",
    "HTTP-Referer": "https://raycast-llm-translate.local",
    "X-Title": "Raycast LLM Translate",
  };
}
