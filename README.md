# LLM Translate for Raycast

Select text in **any app**, press a hotkey, and the translation appears as a sleek pill at the
bottom of your screen — then fades away. Translation is done by a fast, cheap LLM via
[OpenRouter](https://openrouter.ai). Built as a personal replacement for Raycast's built-in
(Google-based) translator.

## Features

- **Pill overlay** — a native macOS panel, not a notification: wraps long translations over
  multiple lines, shows a thin **countdown line** that drains until the pill fades,
  **pauses while you hover** it, never steals keyboard focus. (Raycast's own HUD/toast is
  single-line with a fixed duration, hence the tiny Swift helper.)
- **Instant feedback** — an animated "Translating…" indicator appears the moment the hotkey
  is pressed.
- **Auto language direction** between two configurable languages (default **German ↔ English**):
  text in the primary language is translated to the secondary one, everything else to the
  primary.
- **Clipboard fallback** when no text is selected.
- Second command **"Translate Selection (Window)"** — full Raycast window with streaming
  output and paste / copy / force-direction actions; useful for very long texts.
- Configurable pill duration and model (defaults to `google/gemini-2.5-flash-lite` — a typical
  sentence costs around $0.00001).

## Install

Requires [Raycast](https://raycast.com), Node.js, and the Xcode Command Line Tools (for the
pill helper).

```bash
git clone https://github.com/danielbrammertz/raycast-llm-translate.git
cd raycast-llm-translate
npm install
npm run dev        # wait for "ready", then Ctrl-C — the extension stays installed in Raycast
bash scripts/build-pill.sh   # compiles the pill overlay to ~/.config/raycast-llm-translate/bin/llm-pill
```

Without the pill helper the extension still works and falls back to a single-line Raycast toast.

## API key

Get an OpenRouter API key and provide it either

- in the extension preferences (password field), or
- in `~/.config/raycast-llm-translate/config.json`:

```json
{ "apiKey": "sk-or-v1-…" }
```

(`chmod 600` recommended.) Tip: create a dedicated key with a monthly spend limit and a model
allow-list — a few dollars per month covers heavy everyday use.

## Use

Assign a hotkey in Raycast Settings → Extensions → **LLM Translate → Translate Selection**.
Select text anywhere, press it, read the pill. Hover the pill to keep it; move away and it
fades after the configured duration.

## License

MIT
