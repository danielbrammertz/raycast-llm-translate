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
- **Explain a word while translating English → German** — when the hotkey command translates
  *into* your primary language, the pill splits: the original text on top (smaller font,
  selectable), the translation below. Double-click or drag-select a word/phrase in the original
  text and the bottom area swaps to an elaborate, learner-dictionary-style explanation of it —
  meaning in context, other senses, origin, and a few translations — with the full sentence sent
  along as context. Deselect to go back to the plain translation.
- **Instant feedback** — an animated "Translating…" indicator appears the moment the hotkey
  is pressed.
- **Auto language direction** between two configurable languages (default **German ↔ English**):
  text in the primary language is translated to the secondary one, everything else to the
  primary.
- **Clipboard fallback** when no text is selected.
- Second command **"Translate Selection (Window)"** — full Raycast window with streaming
  output and paste / copy / force-direction actions; useful for very long texts.
- Third command **"Dictionary Lookup"** — press its hotkey and a native input prompt appears (no
  Raycast window, same look as the pill); type a German word or short phrase and get back its
  distinct English meanings/senses (with part of speech and a short disambiguating gloss) in the
  same pill — e.g. "Schloss" → castle / lock / clasp. Direction is fixed (primary → secondary
  language), unlike the auto-detecting hotkey command.
- Configurable pill duration and model (defaults to `google/gemini-2.5-flash-lite` — a typical
  sentence costs around $0.00001).

## Install

Requires [Raycast](https://raycast.com), Node.js, and the Xcode Command Line Tools (for the
native helpers).

```bash
git clone https://github.com/danielbrammertz/raycast-llm-translate.git
cd raycast-llm-translate
npm install
npm run dev        # wait for "ready", then Ctrl-C — the extension stays installed in Raycast
bash scripts/build-helpers.sh   # compiles the pill + input prompt to ~/.config/raycast-llm-translate/bin/
```

Without the pill helper, `Translate Selection` still works and falls back to a single-line
Raycast toast. `Dictionary Lookup` needs the input-prompt helper to have anywhere to type into —
without it, it shows a clear error toast telling you to run the build script above.

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

**Dictionary Lookup** works differently since there's nothing to select: assign it its own hotkey
(same Settings page), press it, and a native input prompt appears — no Raycast window, just the
prompt. Type a word or phrase and press Enter; its meanings show up in the same pill — hover to
keep it up, move away and it fades. Escape, or clicking away from the prompt, cancels it.

## License

MIT
