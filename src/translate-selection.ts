import { Clipboard, Toast, getPreferenceValues, showToast } from "@raycast/api";
import {
  CONFIG_PATH,
  DEFAULT_MODEL,
  OPENROUTER_URL,
  Preferences,
  getInputText,
  openRouterHeaders,
  parseQuickTranslateResult,
  quickTranslateSystemPrompt,
  resolveApiKey,
} from "./translate-core";
import { pillText, showPillOverlay, showSplitPillOverlay } from "./pill";

interface ChatCompletion {
  choices?: { message?: { content?: string } }[];
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

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
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: quickTranslateSystemPrompt(primary, secondary) },
          { role: "user", content: input.text },
        ],
      }),
    });
    if (!resp.ok) {
      const bodyText = await resp.text().catch(() => "");
      throw new Error(`OpenRouter ${resp.status}: ${bodyText.slice(0, 200)}`);
    }
    const data = (await resp.json()) as ChatCompletion;
    const raw = data.choices?.[0]?.message?.content?.trim() ?? "";
    if (!raw) throw new Error("The model returned an empty translation.");

    const parsed = parseQuickTranslateResult(raw);
    const translation = parsed?.translation ?? raw; // never lose a good translation over a formatting hiccup

    if (prefs.copyQuickResult) await Clipboard.copy(translation);

    // Interactive split pill (original text + click-to-explain-a-word) only when translating
    // INTO the primary language — that's the "explain this English word" direction. Falls
    // through to the plain pill for the reverse direction, and if the split pill can't be shown.
    const isPrimaryTarget = parsed?.targetLanguage.trim().toLowerCase() === primary.trim().toLowerCase();
    if (
      isPrimaryTarget &&
      showSplitPillOverlay({ originalText: input.text, translation, primaryLanguage: primary, secondaryLanguage: secondary, apiKey, model }, pillSeconds)
    ) {
      await toast.hide();
    } else if (showPillOverlay(translation, pillSeconds)) {
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
