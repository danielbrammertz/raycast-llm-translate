import { Clipboard, Toast, getPreferenceValues, showToast } from "@raycast/api";
import {
  CONFIG_PATH,
  DEFAULT_MODEL,
  OPENROUTER_URL,
  Preferences,
  dictionarySystemPrompt,
  formatDictionaryPill,
  openRouterHeaders,
  parseDictionarySenses,
  resolveApiKey,
} from "./translate-core";
import { pillText, showPillOverlay } from "./pill";
import { inputBoxAvailable, showInputBox } from "./input-box";

interface ChatCompletion {
  choices?: { message?: { content?: string } }[];
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export default async function DictionaryLookup() {
  if (!inputBoxAvailable()) {
    await showToast({
      style: Toast.Style.Failure,
      title: "Input helper not built",
      message: "Run scripts/build-helpers.sh, then try again",
    });
    return;
  }

  // Shown BEFORE any toast — Raycast's own window never appears in this flow, just the native
  // prompt, so there's nothing to show a toast over yet.
  const term = await showInputBox("German word or phrase…");
  if (!term) return; // cancelled (Escape, clicked away, or left empty)

  const toast = await showToast({ style: Toast.Style.Animated, title: "Looking up…" });
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
  const pillSeconds = parseInt(prefs.pillDuration ?? "20", 10) || 20;

  const apiKey = resolveApiKey(prefs.apiKey);
  if (!apiKey) {
    await fail("No OpenRouter API key", `Set it in the extension preferences or ${CONFIG_PATH}`);
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
          { role: "system", content: dictionarySystemPrompt(primary, secondary) },
          { role: "user", content: term },
        ],
      }),
    });
    if (!resp.ok) {
      const bodyText = await resp.text().catch(() => "");
      throw new Error(`OpenRouter ${resp.status}: ${bodyText.slice(0, 200)}`);
    }
    const data = (await resp.json()) as ChatCompletion;
    const raw = data.choices?.[0]?.message?.content?.trim() ?? "";
    if (!raw) throw new Error("The model returned an empty response.");

    const senses = parseDictionarySenses(raw);
    const pill = senses ? formatDictionaryPill(term, senses) : raw;

    if (prefs.copyQuickResult) await Clipboard.copy(pill);

    if (showPillOverlay(pill, pillSeconds)) {
      await toast.hide();
    } else {
      toast.style = Toast.Style.Success;
      toast.title = pillText(pill);
      await sleep(pillSeconds * 1000);
      await toast.hide();
    }
  } catch (e) {
    const err = e as Error;
    const msg = err.name === "TimeoutError" || err.name === "AbortError" ? "Timed out after 45 s" : err.message;
    await fail("Dictionary lookup failed", msg, 6000);
  }
}
