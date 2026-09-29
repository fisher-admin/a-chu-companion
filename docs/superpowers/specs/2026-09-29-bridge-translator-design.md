# A畜伴侣 — approved design

The user approved the Mac menu-bar utility on 2026-09-29. The final scope is Claude desktop and claude.ai in a browser. Codex, ChatGPT, and other apps are deferred by the user.

## Workflow
Focus a chat input, invoke Control–Option–E, enter Chinese, then press Return or click Translate and Insert. Shift–Return inserts a newline. Return during IME composition must not submit. Capture the destination before activating the utility. Show its app name. Translate with Apple's Translation framework by default; expose an optional user-configured OpenAI-compatible translation service. Keep API keys in Keychain. Preserve numbers, URLs, code, paragraph breaks, and intent in the AI instructions.

Auto-send is opt-in and uses Return or Command–Return according to the selected setting. Never submit on translation error or unverified paste. Do not retry sending automatically. Preserve the Chinese draft and English result on delivery errors. Allow translate-only and explicit copy. Do not retain message history or log message text.

## Target handling
Require Accessibility permission for insertion. Capture the focused element and containing window. Reject secure or non-text controls. Activate and revalidate that exact target before pasting and before optional send. Abort if the target disappears or focus differs. Confirm inserted text using the accessibility value before optional send; otherwise show that insertion could not be confirmed and leave sending to the user. Preserve and conditionally restore clipboard contents without overwriting subsequent user clipboard changes.

## Completion evidence
Build a double-clickable .app. Run unit tests for input validation, keyboard policy, API request and response handling, destination guards, and clipboard ownership. Exercise a real translation and a dedicated local chat fixture. Inspect the real window. Record separately any target applications and permissions that could not be verified; do not claim universal compatibility.


## Approved additions and current pause
- Product name is A畜伴侣 (user request).
- Automatically translate new Claude English replies into Chinese in the same nonactivating chat window as the composer. Separate tabs and a second reply window were removed at the user’s request. Bind to the exact outbound user message; only decode positively labeled Claude message containers. Coalesce streaming for three seconds, ignore stale translations, stop on navigation. Do not infer replies from whole-window differences.
- A read-current-reply action may attach to an existing conversation without sending a message.
- The user reports Accessibility permission enabled, but verification is pending.
- The user briefly paused runtime testing and then explicitly resumed it. A resumable test plan is saved in TEST_PLAN.md.

- The single-page interface keeps up to 40 local message bubbles in memory; English is expandable. Revalidate the captured destination at the start of each new send, and check that snapshot again before pasting.
