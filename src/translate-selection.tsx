import {
  Action,
  ActionPanel,
  Clipboard,
  Detail,
  Icon,
  Toast,
  getPreferenceValues,
  getSelectedText,
  openExtensionPreferences,
  showToast,
} from "@raycast/api";
import { useEffect, useMemo, useRef, useState } from "react";
import fs from "fs";
import os from "os";
import path from "path";

interface Preferences {
  primaryLanguage: string;
  secondaryLanguage: string;
  model: string;
  apiKey?: string;
}

interface State {
  loading: boolean;
  inputSource?: "selection" | "clipboard";
  output: string;
  error?: string;
}

const CONFIG_PATH = path.join(os.homedir(), ".config", "raycast-llm-translate", "config.json");

function resolveApiKey(prefKey: string | undefined): string | undefined {
  if (prefKey && prefKey.trim().length > 0) return prefKey.trim();
  try {
    const cfg = JSON.parse(fs.readFileSync(CONFIG_PATH, "utf8")) as { apiKey?: string };
    if (cfg.apiKey && cfg.apiKey.trim().length > 0) return cfg.apiKey.trim();
  } catch {
    // missing/unreadable config file — reported by caller
  }
  return undefined;
}

async function getInputText(): Promise<{ text: string; source: "selection" | "clipboard" } | undefined> {
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

export default function TranslateSelection() {
  const prefs = useMemo(() => getPreferenceValues<Preferences>(), []);
  const [state, setState] = useState<State>({ loading: true, output: "" });
  const abortRef = useRef<AbortController | null>(null);

  const primary = prefs.primaryLanguage?.trim() || "German";
  const secondary = prefs.secondaryLanguage?.trim() || "English";
  const model = prefs.model || "google/gemini-2.5-flash-lite";

  async function translate(forcedTarget?: string) {
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;

    const apiKey = resolveApiKey(prefs.apiKey);
    if (!apiKey) {
      setState({
        loading: false,
        output: "",
        error: `No OpenRouter API key found. Add one in the extension preferences or in ${CONFIG_PATH}.`,
      });
      return;
    }

    const input = await getInputText();
    if (!input) {
      setState({ loading: false, output: "", error: "No text selected — and the clipboard is empty." });
      return;
    }

    setState({ loading: true, output: "", inputSource: input.source });

    const instruction = forcedTarget
      ? `Translate the user's text into ${forcedTarget}.`
      : `Detect the language of the user's text. If the text is mainly ${primary}, translate it into ${secondary}; otherwise translate it into ${primary}.`;
    const system =
      `You are a translation engine. ${instruction} ` +
      `Preserve meaning, tone, formatting, line breaks, markdown and emoji. ` +
      `Output ONLY the translation — no quotes, no explanations, no language labels.`;

    try {
      const resp = await fetch("https://openrouter.ai/api/v1/chat/completions", {
        method: "POST",
        signal: controller.signal,
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
          "HTTP-Referer": "https://raycast-llm-translate.local",
          "X-Title": "Raycast LLM Translate",
        },
        body: JSON.stringify({
          model,
          temperature: 0.2,
          stream: true,
          messages: [
            { role: "system", content: system },
            { role: "user", content: input.text },
          ],
        }),
      });

      if (!resp.ok || !resp.body) {
        const bodyText = await resp.text().catch(() => "");
        throw new Error(`OpenRouter ${resp.status}: ${bodyText.slice(0, 300)}`);
      }

      const reader = resp.body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";
      let acc = "";
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split("\n");
        buffer = lines.pop() ?? "";
        for (const line of lines) {
          const trimmed = line.trim();
          if (!trimmed.startsWith("data:")) continue;
          const payload = trimmed.slice(5).trim();
          if (payload === "[DONE]") continue;
          try {
            const json = JSON.parse(payload);
            const delta: string = json.choices?.[0]?.delta?.content ?? "";
            if (delta) {
              acc += delta;
              setState((s) => ({ ...s, output: acc }));
            }
          } catch {
            // ignore malformed SSE fragments
          }
        }
      }
      setState((s) => ({
        ...s,
        loading: false,
        output: acc,
        error: acc.length > 0 ? undefined : "The model returned an empty translation.",
      }));
    } catch (e) {
      const err = e as Error;
      if (err.name === "AbortError") return;
      setState((s) => ({ ...s, loading: false, error: err.message }));
      await showToast({ style: Toast.Style.Failure, title: "Translation failed", message: err.message });
    }
  }

  useEffect(() => {
    void translate();
    return () => abortRef.current?.abort();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const markdown = state.error
    ? `⚠️ ${state.error}`
    : state.output.length > 0
      ? state.output
      : state.loading
        ? "*Translating…*"
        : "";

  return (
    <Detail
      isLoading={state.loading}
      markdown={markdown}
      navigationTitle={state.inputSource === "clipboard" ? "LLM Translate (from clipboard)" : "LLM Translate"}
      actions={
        <ActionPanel>
          <Action.Paste title="Paste Translation" content={state.output} />
          <Action.CopyToClipboard title="Copy Translation" content={state.output} />
          <Action
            title={`Force Translate to ${primary}`}
            icon={Icon.ArrowRightCircle}
            shortcut={{ modifiers: ["cmd"], key: "d" }}
            onAction={() => void translate(primary)}
          />
          <Action
            title={`Force Translate to ${secondary}`}
            icon={Icon.ArrowLeftCircle}
            shortcut={{ modifiers: ["cmd"], key: "e" }}
            onAction={() => void translate(secondary)}
          />
          <Action
            title="Open Extension Preferences"
            icon={Icon.Gear}
            shortcut={{ modifiers: ["cmd"], key: "," }}
            onAction={() => void openExtensionPreferences()}
          />
        </ActionPanel>
      }
    />
  );
}
