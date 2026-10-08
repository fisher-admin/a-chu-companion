import AppKit
import ApplicationServices
import CryptoKit

@main struct CLIDeliveryTests {
    static var count = 0, failures = 0
    static func check(_ value: Bool, _ label: String) { count += 1; if !value { failures += 1 }; print((value ? "PASS: " : "FAIL: ") + label) }
    @MainActor static func main() async throws {
        setvbuf(stdout, nil, _IONBF, 0)
        _ = NSApplication.shared
        let binding = "cli-" + String(repeating: "a", count: 64)
        let origin = CLIDeliveryOrigin(pid: 40, tty: "ttys003", started: "Mon Oct 5 11:59:00 2026", tag: "abcdef123456abcdef12")
        let footer = "A畜伴侣 CLI · aaaaaa · project · 输入 abcdef123456abcdef12"
        let empty = "Claude Code\nPrevious answer.\n────────────────\n❯ \n────────────────\n" + footer + "\n? for shortcuts"
        let agentsHint = "⏵⏵ auto mode on (shift+tab to cycle) · ← for agents"
        let table = "| A | B |\n|---|---|\n| 1 | 2 |"
        check(CLIPromptPolicy.footer(screen:empty,binding:binding,origin:origin) != nil,"a strong footer associates the reader independently of input contents")
        check(CLIPromptPolicy.footer(screen:empty+"\nUnknown hint",binding:binding,origin:origin) != nil,"unknown layout text does not gate read identity or manual sending")
        check(CLIPromptPolicy.footer(screen:empty,binding:"cli-other",origin:origin) == nil,"a different session is not selected for reading")
        check(CLIPromptPolicy.footer(screen:empty.replacingOccurrences(of:origin.tag,with:"unknown"),binding:binding,origin:origin) == nil,"a different process marker does not establish a read association")
        check(CLIPromptPolicy.footer(screen:empty+"\n"+footer,binding:binding,origin:origin) == nil,"multiple visible read markers are not guessed")
        check(CLIPromptPolicy.footer(screen:empty.replacingOccurrences(of:footer,with:"A畜伴侣 CLI · aaaaaa · project · 输\n入 "+origin.tag),binding:binding,origin:origin) != nil,"wrapped identity still associates the reader")
        let process = CLIProcessRecord(pid:40,parent:20,group:30,foreground:30,tty:"ttys003",uid:getuid(),started:origin.started,command:"/synthetic/claude")
        check(process.matches(origin), "live foreground process and creation time validate the captured CLI origin")
        var nativeTitle = process; nativeTitle.command = "Claude"
        check(nativeTitle.matches(origin), "native CLI capitalized title is accepted only with the same verified foreground terminal identity")
        var changed = process; changed.foreground = 20
        check(!changed.matches(origin), "a suspended Claude process cannot receive input meant for its shell")
        changed = process; changed.started = "Mon Oct 5 12:01:00 2026"
        check(!changed.matches(origin), "PID reuse does not inherit an old binding")
        changed = process; changed.tty = "ttys004"
        check(!changed.matches(origin), "another terminal device is not the original CLI session")
        let validTag = String(SHA256.hash(data: Data((binding + "\0" + "40" + "\0" + origin.started).utf8)).map { String(format:"%02x",$0) }.joined().prefix(20))
        let verifiedOrigin = CLIDeliveryOrigin(pid:40,tty:origin.tty,started:origin.started,tag:validTag)
        var decoder=BridgeDecoder()
        var packet:[String:Any] = ["version":1,"token":"synthetic-delivery-token","kind":"usage","binding":binding,"epoch":"test-origin","sequence":0,"usage":["rate_limits":[:]],"delivery":["pid":40,"tty":verifiedOrigin.tty,"started":verifiedOrigin.started,"tag":verifiedOrigin.tag]]
        let accepted = try decoder.accept(JSONSerialization.data(withJSONObject:packet),token:"synthetic-delivery-token")
        check(accepted.delivery==verifiedOrigin,"protocol adopts a valid process-bound origin without touching reply contents")
        packet["sequence"]=1;packet["delivery"]=["pid":40,"tty":"??","started":verifiedOrigin.started,"tag":verifiedOrigin.tag]
        do { _ = try decoder.accept(JSONSerialization.data(withJSONObject:packet),token:"synthetic-delivery-token");check(false,"invalid tty rejected") } catch {check(true,"invalid origin is rejected before decoder state changes")}
        packet["delivery"]=["pid":40,"tty":verifiedOrigin.tty,"started":verifiedOrigin.started,"tag":verifiedOrigin.tag]
        let following=try decoder.accept(JSONSerialization.data(withJSONObject:packet),token:"synthetic-delivery-token")
        check(following.delivery==verifiedOrigin && !following.duplicate,"a valid later report remains usable after origin rejection")
        let verifiedEmpty = empty.replacingOccurrences(of:origin.tag,with:validTag)
        let own = NSRunningApplication.current, element = AXUIElementCreateApplication(own.processIdentifier)
        let surface = CLITargetBridge.Surface(app:own,window:element,focus:element,element:element)
        let board = NSPasteboard(name:.init("achu-delivery-"+UUID().uuidString)); defer { board.releaseGlobally() }
        var screen = verifiedEmpty, live = true, focused = true, current = true, events:[CGKeyCode] = []
        var pasteMode = "plain", replaceBoard = false, redrawReads = 0
        var env = CLITargetBridge.Environment()
        env.trusted = { true }; env.alive = { _ in true }; env.screen = { _ in if redrawReads > 0 { redrawReads -= 1; return nil }; return screen }; env.live = { _ in live }
        env.focused = { _, _ in focused }; env.activate = { _ in }; env.board = board
        env.key = { key, _, _ in
            events.append(key)
            if key == 9 {
                let agentsFooter = screen.hasSuffix(agentsHint)
                let previousPrompt = "Existing displayed text"
                let inserted = pasteMode == "collapsed" ? "[Pasted text #1 +120 lines]" : (pasteMode == "append" ? previousPrompt : "") + board.string(forType:.string)!
                screen = verifiedEmpty.replacingOccurrences(of:"❯ ",with:"❯ "+inserted.replacingOccurrences(of:"\n",with:"\n  "))
                if agentsFooter {screen=screen.replacingOccurrences(of:"? for shortcuts",with:agentsHint)}
                if pasteMode == "redraw" { redrawReads = 2 }
                if pasteMode == "exit" { live = false }
                if pasteMode == "switch" { focused = false }
                if pasteMode == "retire" { current = false }
                if replaceBoard { board.clearContents(); board.setString("User's newer clipboard",forType:.string) }
            }
        }
        let driver = CLITargetBridge(environment:env)
        let bound = try driver.bind(surface:surface,session:binding,origin:verifiedOrigin)
        board.clearContents(); board.setString("Original clipboard",forType:.string)
        for text in ["Hello.", "First line.\nSecond line.", table, "/explain", "! Explain this example.", String(repeating:"long ",count:300)] {
            events=[];screen=verifiedEmpty
            let sent=try await driver.deliver(text,to:bound,autoSend:true,current:{current})
            check(sent == .sendKeyPressed && events == [9,36],"manual destination receives one paste and Return for every text shape")
        }
        check(board.string(forType:.string)=="Original clipboard","a successful paste restores the previous clipboard")
        screen=verifiedEmpty;events=[]
        let inserted=try await driver.deliver("Hello.",to:bound,autoSend:false,current:{current})
        check(inserted == .inserted && events == [9],"turning off automatic send pastes once without Return")
        let suggestion=verifiedEmpty.replacingOccurrences(of:"❯ ",with:"❯ Try explaining this code")
        for mode in ["collapsed","redraw","append"] {
            screen=suggestion;events=[];pasteMode=mode
            let result=try await driver.deliver("Hello.",to:bound,autoSend:true,current:{current})
            check(result == .sendKeyPressed && events == [9,36],"rendered contents and receipt shape never gate the manually chosen input")
        }
        for mode in ["switch","retire"] {
            screen=verifiedEmpty;events=[];pasteMode=mode;focused=true;current=true
            let result=try await driver.deliver("Hello.",to:bound,autoSend:true,current:{current})
            if case .submitFailed = result {check(events == [9],"a changed physical focus or replaced connection stops Return after one paste")}
            else {check(false,"a changed physical focus or replaced connection stops Return after one paste")}
        }
        focused=true;current=true;events=[];pasteMode="plain";replaceBoard=true
        _=try await driver.deliver("Hello.",to:bound,autoSend:false,current:{current})
        check(board.string(forType:.string)=="User's newer clipboard","a newer clipboard is not overwritten by restoration")
        replaceBoard=false
        screen=suggestion; events=[]; replaceBoard=false
        do { _ = try driver.bind(surface:surface,session:binding,origin:verifiedOrigin);check(true,"visible CLI prompt suggestions do not prevent binding the verified input window") }
        catch { check(false,"visible CLI prompt suggestions must not be mistaken for a blocking draft") }
        do {
            let result=try await driver.deliver("Hello.",to:bound,autoSend:true,current:{current})
            check(result == .sendKeyPressed && events == [9,36],"a normal paste dismisses the visible suggestion and sends only the exact translation")
        } catch {check(false,"visible suggested text must allow the normal CLI paste path")}
        screen=verifiedEmpty.replacingOccurrences(of:"❯ ",with:"❯ Existing draft");events=[];pasteMode="append"
        do {
            let result=try await driver.deliver("Hello.",to:bound,autoSend:true,current:{current})
            check(result == .sendKeyPressed && events == [9,36],"rendered input contents do not override the user-selected destination")
        } catch {check(false,"existing display text is allowed through paste and checked using actual receipt")}

        screen=suggestion; events=[]; pasteMode="plain";live=true;focused=true;current=true
        let model = TranslatorModel(permissionCheck:{true},remoteKeyRead:{_ in "synthetic-value"},cliDelivery:driver)
        model.cliCapture = {surface}; model.cliEntryRequest = {_ in}
        defer { model.bridge.stop(); model.cancel(); model.stopPermissionMonitoring() }
        model.bridge.start()
        func client(_ mode:String = "report") async throws {
            let path=model.bridge.connectionPath
            let result = try await Task.detached {
                let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/bin/python3");p.arguments=["Tests/CLIDeliveryClient.py",path,mode]
                try p.run();p.waitUntilExit();return p.terminationStatus
            }.value
            check(result==0,"authenticated synthetic \(mode) reaches the production coordinator")
        }
        let captured=TargetBridge.Target(app:own,element:element,window:element,value:verifiedEmpty,selection:nil,conversation:nil,
            identity:.init(role:"AXGroup",identifier:nil,description:nil,placeholder:nil))
        model.connectCapturedTarget(captured)
        check(!model.showCLIPicker,"shortcut capture must wait for its current footer without asking the user to choose a CLI session")
        try await client()
        check(model.hasTarget && model.isCLIConnection && model.bridge.selected==binding,"shortcut sender is independent and a matching footer associates only the reader")
        check(model.hasTarget && model.cliConnectionHint.isEmpty,"suggestion text does not leave a stale nonempty-input error after shortcut binding")
        if !model.hasTarget { screen=verifiedEmpty;model.connectCapturedTarget(captured) }
        try await client("delta")
        check(model.hasTarget && model.replies.watching,"incoming CLI reply snapshots keep the verified outgoing target")
        screen=suggestion
        model.engine="gemini";model.language = .english; model.autoSend=true;model.testTranslation={_ in "Hello."};model.input="你好"
        model.begin(insert:true)
        let deadline=Date().addingTimeInterval(3)
        while model.busy && Date()<deadline { try await Task.sleep(for:.milliseconds(10)) }
        check(!model.busy && model.output=="Hello." && events==[9,36],"Chinese input follows translation through the actual CLI delivery controller")
        check(model.input.isEmpty && model.hasTarget,"successful sending clears the Chinese draft while retaining the CLI binding")
        for (source, translation) in [
            ("请运行20次。", "Please run 30 times."),
            ("请保留原有设置。", "Please retain the settings. They are fine."),
            ("结果可靠吗？", "The result is reliable."),
            ("请保留原有设置。", "请保留原有设置。")
        ] {
            screen=verifiedEmpty;events=[];model.input=source
            model.testFallback={_ in translation}
            model.testTranslation={_ in translation};model.begin(insert:true)
            let completion=Date().addingTimeInterval(3)
            while model.busy && Date()<completion {try await Task.sleep(for:.milliseconds(5))}
            check(!model.busy && model.output==translation && events==[9,36] && model.input.isEmpty,
                "translation quality heuristics do not block automatic CLI paste and Return")
        }
        model.testTranslation={_ in throw BridgeError.message("Gemini 翻译服务返回 503。")}
        var fallbackCalls=0
        model.testFallback={_ in fallbackCalls += 1; return "Hello."}
        screen=verifiedEmpty;events=[];model.input="你好";model.begin(insert:true)
        while model.busy {try await Task.sleep(for:.milliseconds(5))}
        check(events==[9,36] && model.input.isEmpty && model.hasTarget && fallbackCalls==1,"Gemini failure preserves the CLI target and automatically pastes and sends the system translation")
        check(model.status.contains("系统翻译") && model.status.contains("Gemini") && model.status.contains("503") && !model.status.contains("请检查后"),"automatic system fallback retains the remote error without requiring an extra review click")
        screen=verifiedEmpty;events=[];model.autoSend=false;model.input="你好";model.begin(insert:true)
        while model.busy {try await Task.sleep(for:.milliseconds(5))}
        check(events==[9] && model.input.isEmpty,"system fallback preserves disabled automatic sending and still fills the CLI input")
        screen=verifiedEmpty;events=[];model.autoSend=true;model.input="你好";model.begin(insert:false)
        while model.busy {try await Task.sleep(for:.milliseconds(5))}
        check(events.isEmpty && model.input=="你好" && model.output=="Hello." && !model.status.contains("请检查后"),"translation-only fallback never inserts or sends despite automatic sending being selected")
        var waitingFallback:CheckedContinuation<String,Error>?
        model.testFallback={_ in try await withCheckedThrowingContinuation {waitingFallback=$0}}
        screen=verifiedEmpty;events=[];model.input="你好";model.begin(insert:true)
        while waitingFallback==nil {try await Task.sleep(for:.milliseconds(5))}
        model.input="保留新草稿";waitingFallback?.resume(returning:"Hello.");waitingFallback=nil
        while model.busy {try await Task.sleep(for:.milliseconds(5))}
        check(events.isEmpty && model.input=="保留新草稿" && model.output=="Hello.","a draft edited during the system fallback is never replaced or sent")
        model.input="你好";model.begin(insert:true)
        while waitingFallback==nil {try await Task.sleep(for:.milliseconds(5))}
        model.cancel();waitingFallback?.resume(returning:"Hello.");waitingFallback=nil
        try await Task.sleep(for:.milliseconds(30))
        check(events.isEmpty && model.input=="你好" && !model.busy,"cancelling a system fallback retires the late result before paste or Return")
        model.testFallback={_ in throw BridgeError.message("系统翻译暂不可用。")}
        model.input="你好";model.begin(insert:true)
        while model.busy {try await Task.sleep(for:.milliseconds(5))}
        check(events.isEmpty && model.input=="你好" && model.isError && model.output.isEmpty,"both translation services failing preserves the draft without any terminal input")
        let beforeDeliveryFailure=fallbackCalls
        model.testFallback={_ in fallbackCalls += 1; focused=false;return "Hello."}
        screen=verifiedEmpty;events=[];model.input="你好";model.begin(insert:true)
        while model.busy {try await Task.sleep(for:.milliseconds(5))}
        check(events.isEmpty && model.output=="Hello." && model.input=="你好" && model.isError && fallbackCalls==beforeDeliveryFailure+1,"focus lost after system translation retains the candidate without repeating translation or terminal input")
        focused=true;model.testFallback={_ in "Hello. 123"};model.input="你好";model.begin(insert:true)
        while model.busy {try await Task.sleep(for:.milliseconds(5))}
        check(events==[9,36] && model.output=="Hello. 123" && model.input.isEmpty && !model.isError,"system fallback sends without a numeric quality gate")
        model.testFallback={_ in "Hello."};screen=verifiedEmpty;events=[];live=false;model.input="你好"
        model.begin(insert:true)
        while model.busy {try await Task.sleep(for:.milliseconds(5))}
        check(events==[9,36] && model.input.isEmpty,"a missing read-process report does not gate the manually selected input")
        live=true;model.testFallback=nil
        screen=verifiedEmpty; events=[]
        var delayed:CheckedContinuation<String,Error>?
        model.testTranslation={_ in try await withCheckedThrowingContinuation {delayed=$0} };model.input="你好";model.begin(insert:true)
        while delayed==nil { try await Task.sleep(for:.milliseconds(5)) }
        model.bridge.select("cli-"+String(repeating:"b",count:64))
        delayed?.resume(returning:"Hello.");delayed=nil
        while model.busy { try await Task.sleep(for:.milliseconds(10)) }
        check(events==[9,36] && model.output=="Hello." && model.input.isEmpty,"switching the reader does not change or stop the manually pinned sender")
        check(model.hasTarget && model.replies.watching,"a different read source never replaces the manually chosen input")
        screen=verifiedEmpty.replacingOccurrences(of:validTag,with:"waiting-for-footer")
        model.connectCapturedTarget(captured)
        try await client("read-only")
        model.bridge.select(binding)
        check(model.hasTarget,"a captured surface can send independently of report timing or footer text")
        screen=verifiedEmpty
        try await client("refresh")
        check(model.hasTarget,"a late valid identity must bind the captured surface of the same selected session without another shortcut or selection")
        model.cliCapture={throw BridgeError.message("Synthetic capture unavailable")}
        model.connectCapturedTarget(captured)
        check(!model.showCLIPicker && model.status.contains("Synthetic capture unavailable"),"a failed shortcut exposes the input capture cause instead of opening a misleading read-only picker")
        print("\(count) CLI input policy checks; \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
