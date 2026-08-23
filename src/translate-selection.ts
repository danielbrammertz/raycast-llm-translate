import { Clipboard, Toast, getPreferenceValues, showHUD, showToast } from "@raycast/api";
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

function pillText(t: string): string {
  const oneLine = t.replace(/\s*\n+\s*/g, "  ·  ").trim();
  return oneLine.length > 350 ? `${oneLine.slice(0, 347)}…` : oneLine;
}

export default async function TranslateSelectionQuick() {
  const prefs = getPreferenceValues<Preferences>();
  const primary = prefs.primaryLanguage?.trim() || "German";
  const secondary = prefs.secondaryLanguage?.trim() || "English";
  const model = prefs.model || DEFAULT_MODEL;

  const apiKey = resolveApiKey(prefs.apiKey);
  if (!apiKey) {
    await showHUD(`⚠️ No OpenRouter API key — set it in the extension preferences or ${CONFIG_PATH}`);
    return;
  }

  const input = await getInputText();
  if (!input) {
    await showHUD("⚠️ No text selected — and the clipboard is empty");
    return;
  }

  const toast = await showToast({ style: Toast.Style.Animated, title: "Translating…" });
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
    await toast.hide();
    await showHUD(pillText(translation));
  } catch (e) {
    const err = e as Error;
    const msg = err.name === "TimeoutError" || err.name === "AbortError" ? "Timed out after 45 s" : err.message;
    toast.style = Toast.Style.Failure;
    toast.title = "Translation failed";
    toast.message = msg;
  }
}
