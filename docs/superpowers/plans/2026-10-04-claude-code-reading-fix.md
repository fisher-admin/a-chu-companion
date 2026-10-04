# Claude Desktop Code reading repair — 2026-10-04

## Evidence and acceptance

The installed 1.1.4 displayed `Claude 对话页面已关闭或切换，自动读取已停止。` while the bound desktop window remained open in Code mode. Its accessibility web area uses `https://claude.ai/epitaxy/<session>`, which the existing Chat-only route guard rejected. Five non-pending read failures pause the monitor.

The same window exposes `Chat messages`, but Code uses `Message N` instead of `Message N of M`. An author heading lives inside the ordinal marker; subsequent answer paragraphs, tool activity and final actions are siblings through the next marker. The final status is `Claude finished the response`, with `Copy` and `Fork from here` actions. Evidence here records interface structure only, without private conversation content or session identifiers.

Success means the already bound window can follow both Chat and Code conversations; Code collects the entire authored reply, excludes tool cards and actions, waits throughout active work, emits after completion and stability, and preserves explicit stop and unsafe-target safeguards. Existing Chat validation and the fixed application signing identity remain intact.

## Implementation and verification

1. Reproduce missing Code body in a sanitized regression before changing the decoder.
2. Classify only known HTTPS Claude Chat and Code routes. Group Code siblings by ordered ordinal boundaries; retain the author-heading requirement and retry incomplete snapshots.
3. Decode Code content separately, preserving code and final paragraphs while pruning tool cards, duplicate activity labels and actions. Active work/stop indicators override completion indicators.
4. Exercise Code route isolation, grouping, virtualized history, partial thinking, final actions and twenty minutes of simulated work. Repeat existing regression, HTTP and signing checks.
5. Install 1.1.5 build 29 using the existing signer. Test the local twelve-second Code fixture and read an existing real Code response, without sending a real Claude message. Record observed results and remaining gaps in TEST_PLAN.
6. Preserve prior changelog, commits and release tags; submit the fix on its own branch.

## Live refinement

The first native trial stayed connected but found no original. A temporary, text-free diagnostic showed one recognized author, three text nodes and a single range member containing only the header/tool anchor. The final selection flattens only transcript wrapper branches containing structural ordinal anchors, preserving other subtrees intact; body siblings remain associated until the next ordinal. Description/title ordinal attributes are considered independently and conflicting ordinals stay pending. Static text and buttons cannot create message boundaries. Authorship remains confined to the ordinal anchor, with heading value/title handling retained. Temporary diagnostics were removed from the final source.

## Completed segments — user steering

The user subsequently requested timely translation of finished formal segments during ongoing Code work and selected separate records per segment. Tool activity establishes the end of preceding formal text; the trailing segment stays unfinished until another tool boundary or the global finished state. Stable completed segments enter the existing sequential translation queue with `(message ordinal, segment)` identities. Later segments do not cancel earlier complete jobs. Chat keeps its existing completion behavior. The total 50,000-character original limit still applies before segmentation; oversized originals remain intact. The existing ten-record retention now counts each completed segment as one record, matching the selected separate display. Build30 implements this extension; native evidence is recorded separately from build29.

## Stable text — corrected timing

The user observed that build30 still waited until all output arrived and clarified that stable formal text must translate immediately, without a subsequent tool boundary. A new regression failed on the existing tracker because the open segment's `completed == false` prevented emission even after three seconds. Build31 makes Code segments eligible for the existing three-second text stability interval while keeping the decoder's completion flag for manual history selection. Changed text invalidates an active or queued candidate, resets the quiet interval, and updates the same segment identity when stable. Overall completion without text changes produces no duplicate. Chat and whole-reply limit fallbacks keep their original completion rules. The native local fixture now delays the next tool until eighteen seconds and task completion until thirty-six seconds, so early Chinese display can be distinguished from final-only translation.
