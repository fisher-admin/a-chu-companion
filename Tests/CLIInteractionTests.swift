import Foundation
import AppKit

@main struct CLIInteractionTests {
    static var count=0, failures=0
    static func check(_ value: Bool,_ label:String) {count += 1;if !value {failures += 1};print((value ? "PASS: ":"FAIL: ")+label)}
    @MainActor static func main() async throws {
        setvbuf(stdout,nil,_IONBF,0)
        let marker="A畜伴侣 CLI · aaaaaa · project · 输入 abcdef123456abcdef12"
        let menu="Do you want to proceed?\n  Bash command\n  python3 /synthetic/test.py\n❯ 1. Yes\n  2. Yes, and don't ask again\n  3. No\nEnter to confirm · Esc to cancel"
        let parsed=CLIInteractionPolicy.notice(screen:menu)
        check(parsed?.kind == .permission,"a current permission question is separated from formal assistant replies")
        check(parsed?.choices.map(\.key) == ["1.","2.","3."],"choice keys and their order are retained")
        check(parsed?.details.contains("python3 /synthetic/test.py") == true,"command text is retained without execution or rewriting")
        let cursorMoved=menu.replacingOccurrences(of:"❯ 1.",with:"  1.").replacingOccurrences(of:"  3.",with:"❯ 3.")
        check(parsed != nil && parsed?.identity == CLIInteractionPolicy.notice(screen:cursorMoved)?.identity,"moving the selection cursor does not create another translation job")
        let modelMenu="Select model\n❯ 1. Default\n  2. Sonnet\n  3. Opus\nEnter to confirm · Esc to cancel"
        check(CLIInteractionPolicy.notice(screen:modelMenu)?.kind == .selection,"model selectors are read independently of font and terminal brand")
        let combinedHint="⏵⏵ auto mode on (shift+tab to cycle) · ← for agents"
        check(CLIInteractionPolicy.notice(screen:menu+"\n"+marker+"\n"+combinedHint)?.kind == .permission,"known combined input hints do not hide a permission menu")
        check(CLIInteractionPolicy.notice(screen:spinnerWithHint(combinedHint))?.kind == .status,"known combined hints do not hide a running notice")
        let commandBefore="Bash command\n  python3 /synthetic/test.py\nDo you want to proceed?\n❯ 1. Yes\n  2. No\nEsc to cancel · Tab to amend"
        check(CLIInteractionPolicy.notice(screen:commandBefore)?.details.contains("python3 /synthetic/test.py") == true,"permission command context above the question is preserved")
        let trust="Do you trust the files in this folder?\n❯ 1. Yes, I trust this folder\n  2. No, exit\nEnter to confirm · Esc to cancel"
        check(CLIInteractionPolicy.notice(screen:trust)?.kind == .permission,"workspace trust choices are displayed as permission prompts without selecting them")
        check(CLIInteractionPolicy.notice(screen:"❯ Explain a numbered list\n"+marker+"\n? for shortcuts") == nil,"an ordinary input draft is not an operational notice")
        check(CLIInteractionPolicy.notice(screen:"Example in an old answer:\n1. Yes\n2. No\n❯ \n"+marker+"\n? for shortcuts") == nil,"numbered examples in scrollback are not current choices")
        check(CLIInteractionPolicy.notice(screen:menu+"\nfisher@host %") == nil,"a shell prompt following an old menu invalidates the notice")
        let spinner="✻ Thinking… (ctrl+c to interrupt)"
        check(CLIInteractionPolicy.notice(screen:spinner)?.kind == .status,"running notices are captured while a formal reply is still pending")
        let timedSpinner="✻ Thinking… (5s · ↓ 20 tokens)"
        let updatedSpinner="✽ Thinking… (6s · ↓ 30 tokens)"
        check(CLIInteractionPolicy.notice(screen:timedSpinner)?.kind == .status,"a running TUI notice with only time and token counters is recognized")
        check(CLIInteractionPolicy.notice(screen:timedSpinner) != nil && CLIInteractionPolicy.notice(screen:timedSpinner)?.identity == CLIInteractionPolicy.notice(screen:updatedSpinner)?.identity,"spinner glyph and counters do not constantly restart the translation")
        let binding="cli-"+String(repeating:"a",count:64)
        let origin=CLIDeliveryOrigin(pid:40,tty:"ttys003",started:"Mon Oct 5 11:59:00 2026",tag:"abcdef123456abcdef12")
        check(CLIPromptPolicy.prompt(screen:menu+"\n"+marker,binding:binding,origin:origin) == nil,"a visible permission choice never receives a pasted chat message")
        let monitor=CLINoticeMonitor()
        var calls=0
        monitor.translate={text in calls += 1;return text == "Do you want to proceed?" ? "是否继续？" : "选项译文"}
        monitor.observe(screen:menu,identityValid:true,matchingFooter:false,now:1)
        check(monitor.notice == nil,"a markerless menu cannot create trust at initial connection")
        let composer="❯ \n"+marker+"\n? for shortcuts"
        monitor.observe(screen:composer,identityValid:true,matchingFooter:true,now:2)
        monitor.observe(screen:menu,identityValid:true,matchingFooter:false,now:2.5)
        check(monitor.notice?.original == menu && monitor.chinese.isEmpty,"newly captured prompt text is shown immediately before translation")
        monitor.observe(screen:menu,identityValid:true,matchingFooter:false,now:3)
        for _ in 0..<20 {await Task.yield()}
        check(monitor.chinese.contains("是否继续？") && monitor.chinese.contains("1.") && monitor.chinese.contains("3."),"a stable prompt is promptly translated with the original selection keys")
        check(monitor.chinese.contains("python3 /synthetic/test.py"),"command details stay verbatim in the Chinese prompt")
        let previousCalls=calls
        monitor.observe(screen:cursorMoved,identityValid:true,matchingFooter:false,now:3.5)
        for _ in 0..<10 {await Task.yield()}
        check(calls == previousCalls,"cursor movement keeps the existing prompt translation")
        monitor.observe(screen:nil,identityValid:true,matchingFooter:false,now:4)
        monitor.observe(screen:menu,identityValid:true,matchingFooter:false,now:4.5)
        check(monitor.notice == nil,"a read gap breaks markerless trust rather than reviving stale prompts")
        monitor.observe(screen:composer,identityValid:true,matchingFooter:true,now:5)
        monitor.observe(screen:menu,identityValid:false,matchingFooter:false,now:5.5)
        check(monitor.notice == nil,"a changed process or window identity removes the notice")
        monitor.observe(screen:composer,identityValid:true,matchingFooter:true,now:6)
        monitor.observe(screen:menu,identityValid:true,matchingFooter:false,now:10)
        check(monitor.notice == nil,"a long polling gap requires a fresh footer before markerless reading")
        monitor.observe(screen:composer,identityValid:true,matchingFooter:true,now:10.1)
        monitor.observe(screen:menu+"\nA畜伴侣 CLI · bbbbbb · other · 输入 different",identityValid:true,matchingFooter:false,now:10.6)
        check(monitor.notice == nil,"a foreign session footer revokes the markerless capture lease")
        monitor.observe(screen:composer,identityValid:true,matchingFooter:true,now:11)
        var finish:CheckedContinuation<String,Error>?
        monitor.translate={_ in try await withCheckedThrowingContinuation {finish=$0}}
        monitor.observe(screen:menu,identityValid:true,matchingFooter:false,now:11.5)
        monitor.observe(screen:menu,identityValid:true,matchingFooter:false,now:12)
        for _ in 0..<10 {await Task.yield()}
        monitor.reset();finish?.resume(returning:"过期译文")
        for _ in 0..<10 {await Task.yield()}
        check(monitor.notice == nil && monitor.chinese.isEmpty,"late prompt translation cannot repopulate a stopped connection")
        print("\(count) CLI notice checks; \(failures) failed")
        if failures>0 {exit(1)}
    }
    static func spinnerWithHint(_ hint:String) -> String {"✻ Thinking… (5s · ↓ 20 tokens)\n"+hint}
}
