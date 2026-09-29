# A畜伴侣 Implementation Plan

> Execute inline with the executing-plans skill. The user has authorized implementation; no additional design review is needed.

**Goal:** Deliver a native Mac utility that translates Chinese and inserts English into the previously focused chat input.

**Architecture:** SwiftUI window inside an AppKit menu-bar application, with Apple's translation session attached to the window. Isolate validation and API handling from Accessibility delivery, credentials, and the UI.

**Tech Stack:** Swift, SwiftUI, AppKit, Translation, ApplicationServices, Carbon, Security. Build with the installed Swift compiler; no third-party packages.

## Tasks and ownership
- [ ] `Sources/Core.swift`, `Tests/CoreTests.swift`: validate nonempty input (maximum 12,000 characters); implement Return/Shift–Return/IME policy; validate HTTPS or loopback endpoints; construct chat-completions requests; reject HTTP errors, empty/truncated results; guard target identity and clipboard restore. Compile and execute tests, first observing a failing validation test.
- [ ] `Sources/Credentials.swift`, `Sources/TranslatorModel.swift`: store keys in Keychain, persist nonsecret preferences, provide Apple and optional AI translation, prevent duplicate submits, cancel stale results, retain drafts and results on errors. Exercise local mock HTTP success/error/timeout responses without real credentials.
- [ ] `Sources/TargetBridge.swift`: capture focused app/element/window; require permission; reject passwords; activate the captured target and compare identity; paste, verify the value changed as expected, optionally send once; conditionally restore clipboard. Use a local fixture for delivery tests.
- [ ] `Sources/Editor.swift`, `Sources/Views.swift`, `Sources/Main.swift`: Chinese interface, source and result panels, settings, permission guidance, menu-bar item, Control–Option–E shortcut; keyboard tests with real NSTextView marked text and Shift–Return.
- [ ] `build.sh`, `Tests/ChatFixture.swift`, `README.md`: bundle/sign the app, run tests, launch and inspect UI, attempt live translation and fixture delivery. Record evidence and any system-permission blocker in `VERIFICATION.md`.

## Commands
Run `./test.sh` for pure and AppKit tests. Run `./build.sh` for `dist/A畜伴侣.app`. Run `open dist/A畜伴侣.app` for the user interface. Local fixture test uses `dist/A畜伴侣测试输入框.app` and never sends a message to an external recipient.

## Review checklist
Reject empty output, HTTP errors, invalid endpoint schemes, truncated responses, stale operation results, changed targets, and duplicate actions. Check Return composition, Shift–Return newline, translate-only, copy, and both delivery settings. Do not inspect user chat contents or send external test messages. Confirm known limitations are documented in Chinese.
