# AChu Companion · A畜伴侣

**Write in Chinese. Chat with Claude across languages.**

[中文](README.md) · [Help](SUPPORT.md) · [Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md) · [Privacy](docs/PRIVACY.md)

[![CI](https://github.com/fisher-admin/a-chu-companion/actions/workflows/ci.yml/badge.svg)](https://github.com/fisher-admin/a-chu-companion/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

![AChu Companion icon](docs/assets/companion-icon.png)

AChu Companion is a native macOS menu bar app that combines Chinese composition, translated message insertion, Chinese translations of Claude replies, and account usage in one window. Choose English, German, Japanese, or Korean as the conversation language; Chinese remains the primary writing and reading language.

The current formal source release is **1.2.0 · build79**. It publishes the streaming optimization and does not include all features from the separate build78 development branch, including CLI support, native web usage acquisition, dedicated Gemini configuration and table rendering. Known reading, segmentation and scrolling issues remain. Read the [release scope and limitations](docs/releases/1.2.0.md) and [independent review in Chinese](docs/reviews/2026-10-08-claude-1.2.0.md) before installing.

This is an independent community project, not an Anthropic or official Claude product. It reduces copying and switching between tools, but does not guarantee that translated prompts are more accurate than the Chinese originals.

## Features

- **Bidirectional translation:** Chinese to the selected language, foreign-language replies back to Chinese. macOS system translation is the default and requires no API key. Installed language packs are reused.
- **Dual engine with automatic fallback:** Optional Gemini or other OpenAI-compatible AI translation. AI output is checked first (language, length, code fences, inline code, links, added preambles). On timeout, rate limiting (429), a rejected key, or a failed check, that segment is translated by the system instead and a "已改用系统翻译" notice shows the reason. Repeated failures pause AI for a while before it is retried.
- **One-page chat:** Enter submits; Shift+Enter inserts a newline. Enter used to confirm Chinese input-method composition does not submit. Translate only, insert and review, or opt into automatic sending.
- **Streaming translation:** Connecting starts monitoring. Messages entered in the companion or directly in Claude can produce translated replies. While Claude is still writing, each completed sentence or paragraph is translated and shown in source order; code blocks are kept verbatim and never sent for translation. Tool activity and interface controls are excluded from formal replies.
- **Send confirmation and interface-change warning:** After sending, the app checks whether the composer is empty or no longer contains the inserted translation. This is not proof of server receipt and can report a false positive. If Claude's interface stays unreadable for about 45 seconds, a clear warning appears; reading resumes automatically once it recovers.
- **Background operation:** Keep working in another app while reading continues. Closing the companion window hides it; stopping reading or quitting ends monitoring. Keep the connected Claude conversation window open.
- **Conversation following and history:** Reading follows conversation changes in the same connected window. Reconnect the composer before sending to another conversation. Select from visible, completed historical replies for on-demand translation.
- **Long-response reading:** New translations open at the beginning, with scrolling and expandable originals. Chinese text sizes are 12, 14, and 16; default 14. Language and text-size preferences persist.
- **Temporary history:** Keep the latest ten completed reply translations during this run; clear on exit. Clearing records preserves drafts, the Claude conversation, and monitoring.
- **Account usage:** Progress bars, used percentages, and reset times for reported five-hour and weekly limits. Refresh when replies are acquired. Use the desktop login or a specified session; missing data is not shown as zero.
- **Native appearance:** A pig-head menu icon with a capital A, translucent materials following system appearance, and compact controls.

## Requirements and scope

| Item | Current scope |
| --- | --- |
| Hardware | Apple Silicon Mac; current build script targets arm64 |
| macOS | Minimum deployment target 15; mainly tested on 26 |
| Chat clients | Claude Desktop and claude.ai in Chrome |
| Translation | macOS system translation; optional Gemini or other OpenAI-compatible service with automatic fallback to system translation |
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

## Using Gemini

1. Create an API key in [Google AI Studio](https://aistudio.google.com/apikey).
2. Open the companion's translation settings, choose AI translation, and click "使用 Gemini 地址" (`https://generativelanguage.googleapis.com/v1beta/openai/`).
3. Enter an available Gemini model, for example `gemini-2.5-flash` (use a model Google currently lists), turn on "新增或更换 API 密钥", paste the key and save.

The key is stored only in macOS Keychain. Requests use a fixed translation instruction, examples and `temperature: 0`, with the source wrapped in `<source>` tags so the model translates rather than answers or follows it. When AI is unavailable the system engine takes over, so install the language packs for your chosen language under system translation first.

## Updates and history

```bash
git pull --ff-only
./install.sh
```

Installation validates the existing identity. Failed builds or identity mismatches leave the installed app intact. Language, text size, and installed language packs are retained; runtime chat history clears on exit.

[CHANGELOG](CHANGELOG.md) summarizes versions. The [original README archive](docs/DEVELOPMENT_HISTORY.zh-CN.md) and [TEST_PLAN](TEST_PLAN.md) preserve development and verification history. Git history is retained; release tags identify actual source commits.

## Data and privacy

Default system translation requires no translation API key; initial language-pack downloads may need a network connection. Optional AI translation sends Chinese drafts and foreign replies to your configured provider, under that provider's pricing and data policies. Streaming translation splits one reply into several shorter requests.

Translations placed on the clipboard for insertion carry transient and concealed markers requesting that cooperating clipboard managers ignore them; third-party tools may not honour these markers. Disconnecting or quitting switches off the accessibility options the companion enabled in Claude or Chrome for reading.

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

The current app has 273 regression checks plus seven loopback HTTP checks. On a Mac with installed language packs, `./test-languages.sh` verifies real system round trips and streamed "AI rate-limited → system translation" fallback. Native validation covers continuous replies, slow responses, background reading, history selection, stop/resume, preferences, and replies approaching 50,000 characters. Untested browser/OS combinations are not presented as verified.

## Community and license

[Report issues](https://github.com/fisher-admin/a-chu-companion/issues/new/choose), propose improvements, or submit pull requests. Read [Contributing](CONTRIBUTING.md), [Code of Conduct](CODE_OF_CONDUCT.md), and [Support](SUPPORT.md).

Licensed under the [MIT License](LICENSE). Anthropic, Claude, Apple, and other trademarks belong to their respective owners; the project license grants no rights to third-party trademarks.
