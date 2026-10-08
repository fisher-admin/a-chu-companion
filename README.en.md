# AChu Companion · A畜伴侣

**Write in Chinese. Chat with Claude across languages.**

[中文](README.md) · [Help](SUPPORT.md) · [Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md) · [Privacy](docs/PRIVACY.md)

[![CI](https://github.com/fisher-admin/a-chu-companion/actions/workflows/ci.yml/badge.svg)](https://github.com/fisher-admin/a-chu-companion/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

![AChu Companion icon](docs/assets/companion-icon.png)

AChu Companion is a native macOS menu bar app that combines Chinese composition, translated message insertion, Chinese translations of Claude replies, and account usage in one window. Choose English, German, Japanese, or Korean as the conversation language; Chinese remains the primary writing and reading language.

This is an independent community project, not an Anthropic or official Claude product. It reduces copying and switching between tools, but does not guarantee that translated prompts are more accurate than the Chinese originals.

## Current development changes

Formal originals appear immediately, while stable fragments are automatically translated before the whole turn ends. Existing Chinese prefixes, reading position, and text selection are preserved. Compatible-service credentials are isolated by endpoint; OpenAI/Grok presets retain separate model choices, while native Gemini stays unchanged. Passive health checks do not generate text.

Usage/statusLine sources and read-only CLI/Chrome adapters remain experimental. After initial adapter setup, connecting a chat source automatically follows its usage without a separate usage-account confirmation. Settings provide supplementary acquisition and setup; unavailable identity clears previous values rather than falling back to another channel.

**1.1.8 build66 is installed under the unchanged signing identity.** All 32 offline groups passed 585 declared checks and 19 loopback HTTP checks; unchanged bridge modules retain build65 verification. Actual four-language system round trips and 49,031-character / 1,400-paragraph translation passed. Cooldown sharing, bounded recovery, current-entrance usage isolation and translation safeguards were independently tested, including review of an observed training-fold/discount conflict and matching indirect questions. Full live Desktop/Web/visible CLI acceptance remains incomplete and is tracked in the [execution record](docs/testing/optimization-results-2026-10-07.md). The [build58 record](docs/testing/three-channel-active-usage-2026-10-07.md) and [Claude build63 review](docs/testing/claude-change-review-2026-10-07.md) preserve earlier failures and limits.

## Features

- **Bidirectional translation:** Chinese to the selected language, completed foreign-language replies back to Chinese. macOS system translation is the default and requires no API key. Installed language packs are reused.
- **Gemini translation:** Choose Google's native API with Gemini 3.1 Flash-Lite pinned by default. Outgoing and incoming translations share the selected configuration, with a bidirectional connection check and a separate Keychain credential.
- **One-page chat:** Enter submits; Shift+Enter inserts a newline. Enter used to confirm Chinese input-method composition does not submit. Translate only, insert and review, or opt into automatic sending.
- **Continuous reading:** Connecting starts monitoring. Messages entered in the companion or directly in Claude can produce translated replies. Original text appears before Chinese; tool activity and interface controls are excluded from formal replies.
- **Background operation:** Keep working in another app while reading continues. Closing the companion window hides it; stopping reading or quitting ends monitoring. Keep the connected Claude conversation window open.
- **Conversation following and history:** Reading follows conversation changes in the same connected window. Reconnect the composer before sending to another conversation. Select from visible, completed historical replies for on-demand translation.
- **Long-response reading:** New translations open at the beginning, with scrolling and expandable originals. Chinese text sizes are 12, 14, and 16; default 14. Language and text-size preferences persist.
- **Temporary history:** Keep the latest ten completed reply translations during this run; clear on exit. Clearing records preserves drafts, the Claude conversation, and monitoring.
- **Account usage:** Connecting a chat automatically follows its Desktop, Web, or CLI source. Show reported five-hour/weekly percentages and reset times; settings supplement first-time adapter setup and acquisition. Missing data is not zero, and a repeated CLI report does not imply a fresh server query.
- **Table translation:** Ordinary tables retain rows, columns and values, with horizontal scrolling and Markdown copy. Gemini uses bounded nearby text to disambiguate cell wording while remaining translation-only. Complex merged tables have not been verified.
- **Code segments:** Formal text starts translating after about three seconds without changes, before another tool event or overall completion. A stable continuation updates its existing segment. Tool progress and output are excluded. Each segment counts toward the ten recent translation records.
- **Native appearance:** A pig-head menu icon with a capital A, translucent materials following system appearance, and compact controls.

## Requirements and scope

| Item | Current scope |
| --- | --- |
| Hardware | Apple Silicon Mac; current build script targets arm64 |
| macOS | Minimum deployment target 15; mainly tested on 26 |
| Chat clients | Claude Desktop (Chat and Code modes) and claude.ai in Chrome |
| Translation | macOS system translation; Google Gemini; configured OpenAI-compatible service |
| Permissions | Accessibility for insertion and reading; possible Keychain authorization for desktop usage |
| Chinese input | Up to 10,000 characters, including punctuation and line breaks |
| Foreign text | Outgoing translations and incoming originals each up to 50,000 characters, not words |

Other browsers, Intel Macs, and actual macOS 15 operation have not received equivalent validation. Claude interface changes, inaccessible historical content, and suspended browser pages can affect reading. Claude's own message, context, and account limits still apply.

## Build and install

Use a recent Swift toolchain (Xcode/Command Line Tools with the macOS 26 SDK) and Python 3. From a clone:

```bash
git clone https://github.com/fisher-admin/a-chu-companion.git
cd a-chu-companion
./setup-signing.sh
./install.sh
open "$HOME/Applications/A畜伴侣.app"
```

First setup creates or reuses a dedicated local signing identity in your login Keychain. Each Mac uses its own identity; no maintainer certificate or login is needed. Installation is at `~/Applications/A畜伴侣.app`.

Releases currently provide source, not a universal Apple Developer ID notarized installer. Local signing preserves update identity; it is not Apple notarization. CI verification bundles are not published as end-user installers.

1. Allow AChu Companion under System Settings → Privacy & Security → Accessibility.
2. Click Claude's message box and press **Control+Option+E** on your physical keyboard.
3. Select a conversation language and enter Chinese in the companion.
4. By default, review and send the inserted translation yourself. To send automatically, enable the send option and choose Enter or Command+Enter.
5. Completed replies are read automatically. Stop, resume, or request historical replies whenever needed.

Permission changes are detected without restarting. Normal updates using the same local signing identity can retain authorization; a new computer, changed identity, or revoked permission may require authorization again.

## Configure Gemini

Open Translation Settings at the top right, choose Gemini, keep `gemini-3.1-flash-lite`, enable the key-update checkbox, and enter your Google AI Studio API key in the masked field. Test Connection checks Chinese-to-English and English-to-Chinese before saving. It sends only two fixed synthetic sentences, does not read the conversation, and does not save an unsubmitted key. Saved provider/model preferences and the Keychain key survive restarts and normal updates.

Gemini calls Google's native `generateContent` endpoint directly, without an OpenAI-compatible base URL. `gemini-flash-latest` is a moving Flash alias and does not pin Flash-Lite. The model has a limited free tier; actual limits depend on the project. Billing-enabled projects may incur charges, and free-tier content may be used to improve Google products. See [Gemini setup and corrected request example](docs/GEMINI_SETUP.md).

## Updates and history

```bash
git pull --ff-only
./install.sh
```

Installation validates the existing identity. Failed builds or identity mismatches leave the installed app intact. Language, text size, and installed language packs are retained; runtime chat history clears on exit.

[CHANGELOG](CHANGELOG.md) summarizes versions. The [original README archive](docs/DEVELOPMENT_HISTORY.zh-CN.md) and [TEST_PLAN](TEST_PLAN.md) preserve development and verification history. Git history is retained; release tags identify actual source commits.

## Data and privacy

Default system translation requires no translation API key; initial language-pack downloads may need a network connection. Gemini sends Chinese drafts and foreign replies directly to Google. Optional compatible AI translation sends them to your configured provider. The selected provider's pricing and data policies apply.

Chat history is not written to disk. Supplied sessions and translation keys live in macOS Keychain. Usage requests are read-only, send session credentials only to the Claude domain, and do not send chat messages. Connect the correct usage account when browser and desktop logins differ.

The target input is checked before delivery; unverifiable insertion is not automatically sent. Oversized content, errors, or cancellation preserve content and show a notice. Long translations are combined only when complete. System translation may alter punctuation in code: inspect the original before executing it.

See [Privacy and permissions](docs/PRIVACY.md). Submit vulnerabilities through [private security reporting](https://github.com/fisher-admin/a-chu-companion/security/advisories/new), without publicly exposing credentials or private conversations.

## Development and validation

```bash
python3 -m unittest discover -s Tests -p RepositoryChecksTests.py
python3 Tools/check_repository.py --history
./test.sh
./test-http.sh
./build.sh --unsigned
```

`--unsigned` writes only to `dist/unsigned/`, does not read local signing configuration, and does not install or overwrite the normal signed bundle. Default build and installation still require the fixed local identity.

GitHub CI performs repository checks, offline regressions, loopback HTTP tests, and certificate-free builds. CodeQL analyzes Swift, Python, and Actions workflows. It does not sign into Claude, send real messages, or install language packs. Language, identity, and actual Claude tests run separately; see [Contributing](CONTRIBUTING.md) and [Verification records](TEST_PLAN.md).

Build66 has 32 offline groups with 585 declared checks and 19 loopback HTTP checks covering paragraph continuity, Gemini bidirectional requests, credential separation, failure feedback, and adaptive long-text retries. Historical native validation covers continuous replies, slow responses, background reading, history selection, stop/resume, preferences, and replies approaching 50,000 characters, with each result tied to its tested version. Actual Google calls, Desktop Code mode, and the experimental CLI adapter are recorded separately. Untested browser, terminal, and OS combinations are not presented as verified.

Build41 removes injected line breaks around inline files, links and emphasis, and handles provider-added line breaks in the shared system/AI translation path while preserving genuine paragraphs, code, lists and table structure. See the [paragraph-layout record](docs/testing/paragraph-layout-2026-10-06.md) for simulations and native UI checks. Earlier Code tests demonstrated an early Chinese stage, but also recorded untranslated stages, table-semantic failures and an exceeded test budget; they do not establish full live acceptance. See the [2026-10-06 supplement report](docs/testing/real-code-supplement-results-2026-10-06.md).

## Community and license

[Report issues](https://github.com/fisher-admin/a-chu-companion/issues/new/choose), propose improvements, or submit pull requests. Read [Contributing](CONTRIBUTING.md), [Code of Conduct](CODE_OF_CONDUCT.md), and [Support](SUPPORT.md).

Licensed under the [MIT License](LICENSE). Anthropic, Claude, Apple, and other trademarks belong to their respective owners; the project license grants no rights to third-party trademarks.
