# Gemini translation configuration — 2026-10-04

## Proposed behavior

Add Gemini as a third translation choice alongside Apple system translation and the existing OpenAI-compatible service. Use Google's native `generateContent` API at a fixed HTTPS Google endpoint, defaulting to the stable `gemini-3.1-flash-lite` model. `gemini-flash-latest` is a moving Flash alias, so it does not pin the requested Flash-Lite model.

Keep Gemini's model preference and API key separate from the existing service. Store the key in macOS Keychain only, never preferences, logs, Git, request URLs, or documentation. The settings sheet accepts a masked key and can verify the connection with fixed, synthetic text. Existing translation settings remain selected until the user saves a new choice. Remember the selected provider/model across restarts and upgrades.

The selected provider handles Chinese-to-English/German/Japanese/Korean and foreign-to-Chinese translation, including automatically read Code segments and selected history. Reuse the existing chunking, cancellation, original-first display and delivery protection. Translate only; preserve intent, negation, numbers, code, links, Markdown and paragraph breaks.

## Alternatives and decision

1. Native Gemini API (recommended): matches the supplied request format and makes Gemini response handling, finish reasons and quota errors explicit.
2. Use an OpenAI-compatible service: can reuse existing settings, but hides native Gemini distinctions behind another request/response format and is less clear for the requested configuration.

## Network and failure behavior

POST `contents` and `systemInstruction` with the key in `X-goog-api-key`. Select one text candidate, exclude thinking parts, require a complete text result, and reject redirects. Preserve originals on invalid keys, disabled access, unknown models, quota/rate limiting, safety blocks, missing output and network failure. Truncated model output triggers the existing smaller-chunk recovery; quota errors do not pretend translation succeeded or silently switch models/services.

Google's documented free tier has project-specific limits. The app cannot ensure a billing-enabled project is free. Settings explain that actual billing/limits depend on the user's Google project and that free-tier content may be used to improve Google products. No paid alternative or automatic provider fallback is selected.

## Completion criteria

- Request/response checks verify both directions, model selection, headers, credential isolation, ignored thinking parts, completion checks, truncation, safety and quota failures.
- Local HTTP checks exercise actual Gemini-shaped requests and responses without sending private conversation data.
- Existing translation, Code reading and signing checks continue to pass; installed settings display and persist correctly.
- With a user-supplied key entered locally, verify synthetic bidirectional translation and connection feedback. Until then, clearly distinguish offline/local checks from successful Google calls.
- Preserve prior versions and verification records; upload only source/test/documentation changes, without keys or private conversation content.

## Sources checked

- https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-lite
- https://ai.google.dev/gemini-api/docs/models
- https://ai.google.dev/gemini-api/docs/pricing
- https://ai.google.dev/api/generate-content

The user approved this design on 2026-10-04. Implementation proceeds in the existing isolated feature branch, without additional design approvals.
