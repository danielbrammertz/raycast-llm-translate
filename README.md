# LLM Translate (Raycast extension)

Personal replacement for Raycast's built-in (Google-based) translation, which stopped working.
Translates the **selected text in any app** via a fast, cheap LLM on OpenRouter and shows the
result in a Raycast window — same UX as the built-in translator.

Two commands:

- **Translate Selection** (the hotkey one) — no window: shows an animated "Translating…" pill
  at the bottom of the screen, then the translation as a pill — the same UX as the old built-in
  translator. Pill duration is configurable in the command's settings (default 6 s; Raycast's
  native HUD can't do this, so the pill is a toast held open by the command). Optional
  preference to also copy the result to the clipboard (off by default).
- **Translate Selection (Window)** — full Raycast window with **streaming** output and actions:
  **⏎ paste translation** (replaces the selection in the frontmost app), copy, force direction
  (⌘D → primary, ⌘E → secondary language). Better for long texts, since the pill is one line.

Both: **German ↔ English by default** (auto-detected, both directions; configurable) and
**clipboard fallback** when no text is selected.

## Setup

1. Install (already done on fritz — only needed again if the extension ever disappears from Raycast):

   ```bash
   cd ~/git/raycast-llm-translate
   npm install && npm run dev     # wait for "ready", then Ctrl-C — the extension stays installed
   ```

2. Assign the hotkey: Raycast Settings → Extensions → **LLM Translate → Translate Selection** →
   Record Hotkey (take over the hotkey from the broken built-in "Translate" extension, and
   disable that one while you're there).

## API key

Read from `~/.config/raycast-llm-translate/config.json` (`chmod 600`), falling back to the
extension preference "OpenRouter API Key" if set. The current key was minted 2026-08-23 via
Cardea (grant `g_Suy04bdjXEQjKo68Lpqp4A`):

- **$10/month budget, resets monthly** — hard-enforced by OpenRouter Guardrails.
- **Model allow-list (enforced):** `google/gemini-2.5-flash-lite` (default),
  `google/gemini-2.5-flash`, `openai/gpt-4.1-nano`, `mistralai/mistral-small-3.2-24b-instruct`.
- **Expires 2027-08-23** — after that, mint a new key through the Cardea `openrouter` entity
  (`mint-native-subkey`, same scope) and replace `apiKey` in the config file.

Check spend anytime:

```bash
curl -s https://openrouter.ai/api/v1/key \
  -H "Authorization: Bearer $(jq -r .apiKey ~/.config/raycast-llm-translate/config.json)" \
  | jq '.data | {usage, limit, limit_remaining}'
```

A typical sentence costs ~$0.00001, so the cap is roughly a million translations/month.

## Cost/model notes

Default model is `google/gemini-2.5-flash-lite` ($0.10/M input, $0.40/M output) — the best
speed/quality/price balance for translation as of 2026-08. Switch models in the extension
preferences (only allow-listed models work; anything else is rejected by OpenRouter with 404).
