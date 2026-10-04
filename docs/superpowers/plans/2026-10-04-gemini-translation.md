# Gemini Translation Implementation Plan

> **For agentic workers:** Use executing-plans to implement this plan inline, task by task. The user's workflow reserves subagents for difficult unresolved decisions.

**Goal:** Add native Gemini translation and a local-key connection check to A畜伴侣.

**Architecture:** A provider enum routes requests, responses and credential accounts. Gemini owns its native JSON format; the existing translation pipeline and Claude reader use the selected provider. Settings keep separate model/key profiles and test only fixed synthetic text.

**Tech Stack:** Swift, SwiftUI, Foundation URLSession, macOS Keychain, existing shell/Python verification tooling.

## 1. Protocol and network checks

- [x] Add `Tests/GeminiTests.swift`, first reproducing the missing provider with `RemoteTranslationProvider(rawValue: "gemini")` and a request assertion for `gemini-3.1-flash-lite:generateContent`.
- [x] Run the test and confirm failure, then implement `Sources/GeminiTranslation.swift` with `RemoteTranslationProvider`, `GeminiProtocol.endpoint`, `request` and `response`.
- [x] Extend `AITranslator.translate(_ request: URLRequest, provider: RemoteTranslationProvider = .openAI)` in `Sources/Core.swift` to choose the proper parser while retaining ephemeral sessions and blocked redirects.
- [x] Test preserved payload text, translation-only instructions, both directions and four languages; exclude thoughts, require STOP, and reject safety/empty/malformed output. MAX_TOKENS maps to the existing smaller-chunk retry. HTTP 401/403/404/429/5xx have clear Gemini errors without response-body disclosure.
- [x] Update explicit Swift compilation lists in `test.sh` and `test-http.sh`; extend `Tests/MockServer.py` and `Tests/HTTPTests.swift` with Gemini-shaped request, redirect, quota and truncation checks.

## 2. Model and credentials

- [x] In `Sources/Credentials.swift`, route Keychain accounts by provider while preserving the original OpenAI-compatible account. Add account-isolation regression coverage without overwriting real credentials.
- [x] In `Sources/TranslatorModel.swift`, add persisted `geminiModel`, expose `activeAIModel`, and route saving, preflight and outgoing chunks through the provider. Defaults remain Apple.
- [x] In `Sources/ReplyMonitor.swift`, route incoming translation requests and credentials through the provider; snapshot provider/model for in-flight jobs.
- [x] Extend `Tests/ModelTests.swift` to verify independent model preferences, persistence, draft/history preservation and missing Gemini credentials before delivery. Restore all changed preferences after tests.

## 3. Settings and connection verification

- [x] Extract `SettingsView` into `Sources/TranslationSettingsView.swift`; add Gemini as a third choice, its model field and masked provider-specific key. Explain Google project limits and free-tier data use.
- [x] Add cancellable connection verification using `GeminiProtocol.request(text: "请保留现有设置。", direction: .fromChinese(.english))` and the reverse direction with fixed English text. Do not send Claude conversation content or save unsaved keys when testing.
- [x] Reset typed keys when switching provider; retire tests on field changes or dismissal. Saving retains unrelated provider preferences/keys and rolls back on failure.
- [ ] Verify the installed sheet visually, provider switching, test feedback and preference persistence. User enters the real key locally for live Google verification.

## 4. Delivery and evidence

- [x] Run `./test.sh`, `./test-http.sh`, repository unit/history checks, `python3 Tests/SigningTests.py`, and `./build.sh --unsigned`. Use normal host permissions for local sockets, icon rendering and the existing signing key.
- [x] Install 1.1.6 build32 with the existing signer; do not renew authorization or replace the signing identity.
- [x] Record actual native/live results separately in TEST_PLAN.md, preserve old entries, and update bilingual README/CHANGELOG plus corrected curl example.
- [ ] Check staged files and Git history for credential patterns, commit/push only source/tests/docs, and create an attached update draft. Never include API keys or private chat contents.
