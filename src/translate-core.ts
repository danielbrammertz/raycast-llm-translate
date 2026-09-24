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
  pillDuration?: string;
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
    "HTTP-Referer": "https://github.com/danielbrammertz/raycast-llm-translate",
    "X-Title": "Raycast LLM Translate",
  };
}

export interface DictionarySense {
  translation: string;
  partOfSpeech?: string;
  note?: string;
}

export function dictionarySystemPrompt(primary: string, secondary: string): string {
  return (
    `You are a bilingual dictionary. The user enters a single ${primary} word or short phrase. ` +
    `List every distinct ${secondary} meaning/sense of it, the way a good bilingual dictionary would: ` +
    `one entry per sense if it has several clearly distinct or unrelated meanings (e.g. homonyms, ` +
    `different registers, idiomatic vs. literal uses), up to about 10 senses ordered from most to least ` +
    `common; just one entry if it really only has one common meaning. ` +
    `Respond with ONLY a single JSON object — no markdown code fences, no commentary before or after it — ` +
    `matching exactly this shape: {"senses":[{"translation":"...","partOfSpeech":"...","note":"..."}]}. ` +
    `"translation" is the ${secondary} word or short phrase for that sense — never the ${primary} ` +
    `source word itself. "partOfSpeech" is a short abbreviation such as "n.", "v.", "adj." or "idiom". ` +
    `"note" is a short (under 12 words), plain-text, disambiguating gloss of that specific sense, ` +
    `written in ${secondary}.`
  );
}

function tryParseJson(s: string): unknown {
  try {
    return JSON.parse(s);
  } catch {
    return undefined;
  }
}

/** Defensively parses the model's JSON response. Handles ```json fences, stray prose around the
 *  JSON object, and a model that ignores the object-wrapping instruction and returns a bare array. */
export function parseDictionarySenses(raw: string): DictionarySense[] | undefined {
  const stripped = raw
    .trim()
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/```\s*$/i, "")
    .trim();
  let parsed = tryParseJson(stripped);
  if (parsed === undefined) {
    const start = stripped.indexOf("{");
    const end = stripped.lastIndexOf("}");
    if (start >= 0 && end > start) parsed = tryParseJson(stripped.slice(start, end + 1));
  }
  if (parsed === undefined) return undefined;

  const list = Array.isArray(parsed) ? parsed : (parsed as { senses?: unknown })?.senses;
  if (!Array.isArray(list)) return undefined;

  const senses = list
    .filter((s): s is Record<string, unknown> => !!s && typeof s === "object" && typeof s.translation === "string")
    .map((s) => ({
      translation: String(s.translation).trim(),
      partOfSpeech: typeof s.partOfSpeech === "string" ? s.partOfSpeech.trim() : undefined,
      note: typeof s.note === "string" ? s.note.trim() : undefined,
    }))
    .filter((s) => s.translation.length > 0);

  return senses.length > 0 ? senses : undefined;
}

export function formatDictionaryPill(term: string, senses: DictionarySense[]): string {
  const lines = senses.map((s, i) => {
    const pos = s.partOfSpeech ? ` (${s.partOfSpeech})` : "";
    const note = s.note ? ` — ${s.note}` : "";
    return `${i + 1}. ${s.translation}${pos}${note}`;
  });
  return [`${term} →`, ...lines].join("\n");
}

export interface QuickTranslateResult {
  targetLanguage: string;
  translation: string;
}

/** Same auto-detect direction as systemPrompt(), but reports which way it went — the caller
 *  needs that to decide whether to show the interactive split pill (target = primary). Kept
 *  separate from systemPrompt() rather than extended: that function is shared with the
 *  streaming window command and its "output ONLY the translation" instruction would directly
 *  contradict an appended JSON-wrapping instruction. */
export function quickTranslateSystemPrompt(primary: string, secondary: string): string {
  return (
    `You are a translation engine. Detect the language of the user's text. If the text is ` +
    `mainly ${primary}, translate it into ${secondary} and set "targetLanguage" to "${secondary}"; ` +
    `otherwise translate it into ${primary} and set "targetLanguage" to "${primary}". Preserve ` +
    `meaning, tone, formatting, line breaks, markdown and emoji in the translation. ` +
    `Respond with ONLY a single JSON object — no markdown code fences, no commentary before or ` +
    `after it — matching exactly this shape: {"targetLanguage":"...","translation":"..."}. ` +
    `"targetLanguage" must be exactly "${primary}" or "${secondary}". "translation" is the ` +
    `translated text only — no quotes, no explanations, no language labels.`
  );
}

/** Same defensive strategy as parseDictionarySenses. */
export function parseQuickTranslateResult(raw: string): QuickTranslateResult | undefined {
  const stripped = raw
    .trim()
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/```\s*$/i, "")
    .trim();
  let parsed = tryParseJson(stripped);
  if (parsed === undefined) {
    const start = stripped.indexOf("{");
    const end = stripped.lastIndexOf("}");
    if (start >= 0 && end > start) parsed = tryParseJson(stripped.slice(start, end + 1));
  }
  if (parsed === undefined) return undefined;

  const obj = parsed as { targetLanguage?: unknown; translation?: unknown };
  if (typeof obj.targetLanguage !== "string" || typeof obj.translation !== "string") return undefined;
  const translation = obj.translation.trim();
  if (!translation) return undefined;
  return { targetLanguage: obj.targetLanguage.trim(), translation };
}
