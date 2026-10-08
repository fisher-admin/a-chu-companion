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
        check(CLIPromptPolicy.prompt(screen: empty, binding: binding, origin: origin)?.isEmpty == true, "current footer with an empty CLI composer permits a verified input binding")
        let blankRows = String(repeating:"\n    ",count:40)
        check(CLIPromptPolicy.prompt(screen:empty+blankRows,binding:binding,origin:origin)?.isEmpty == true,"unused blank terminal rows after the footer do not hide the current empty input surface")
        check(CLIPromptPolicy.prompt(screen:empty+"\nfisher@host %"+blankRows,binding:binding,origin:origin)==nil,"trailing blank rows cannot turn a shell prompt into the Claude input surface")
        check(CLIPromptPolicy.prompt(screen: empty, binding: "cli-" + String(repeating:"b",count:64), origin: origin) == nil, "a different session marker never authorizes input")
        check(CLIPromptPolicy.prompt(screen: empty.replacingOccurrences(of:"abcdef123456abcdef12",with:"999999123456abcdef12"), binding: binding, origin: origin) == nil, "a restarted process footer cannot reuse the previous target")
        check(CLIPromptPolicy.prompt(screen: empty + "\nfisher@host %", binding: binding, origin: origin) == nil, "a shell prompt after Claude's scrollback is not an input destination")
        check(CLIPromptPolicy.prompt(screen: empty + "\nAllow tool?\n1. Yes\n2. No", binding: binding, origin: origin) == nil, "permission menus cannot receive translated prose")
        check(CLIPromptPolicy.prompt(screen: "❯\n"+footer+"\n❯\n"+footer, binding: binding, origin: origin) == nil, "ambiguous mixed panes are rejected rather than guessed")
        let pasted = empty.replacingOccurrences(of:"❯ ",with:"❯ Hello.")
        check(CLIPromptPolicy.receipt(screen:pasted,binding:binding,origin:origin,text:"Hello.") == .confirmed, "short pasted text is verified before sending")
        check(CLIPromptPolicy.receipt(screen:pasted+blankRows,binding:binding,origin:origin,text:"Hello.") == .confirmed,"a padded native terminal still verifies exact pasted text")
        let multiline = empty.replacingOccurrences(of:"❯ ",with:"❯ First line.\n  Second line.")
        check(CLIPromptPolicy.receipt(screen:multiline,binding:binding,origin:origin,text:"First line.\nSecond line.") == .confirmed, "multiline text is compared without visual continuation indentation")
        let table = "| A | B |\n|---|---|\n| 1 | 2 |"
        let tableScreen = empty.replacingOccurrences(of:"❯ ",with:"❯ " + table.replacingOccurrences(of:"\n",with:"\n  "))
        check(CLIPromptPolicy.receipt(screen:tableScreen,binding:binding,origin:origin,text:table) == .confirmed, "table rows and delimiters survive input verification")
        let collapsed = empty.replacingOccurrences(of:"❯ ",with:"❯ [Pasted text #1 +120 lines]")
        check(CLIPromptPolicy.receipt(screen:collapsed,binding:binding,origin:origin,text:String(repeating:"long text",count:200)) == .collapsed, "collapsed paste is distinguished from an exact content receipt")
        check(CLIPromptPolicy.receipt(screen:pasted,binding:binding,origin:origin,text:"Hello. extra") == .mismatch, "partial or truncated pasted text cannot be automatically submitted")
        check(CLIPromptPolicy.prompt(screen:empty.replacingOccurrences(of:"❯ ",with:"❯ ! pwd"),binding:binding,origin:origin)?.isEmpty == false, "an existing shell-mode draft is not an empty composer")
        check(CLIPromptPolicy.prompt(screen:empty.replacingOccurrences(of:"❯ ",with:"❯ /config"),binding:binding,origin:origin)?.isEmpty == false, "existing slash commands cannot be overwritten")
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
        env.focused = { _, _ in focused }; env.companionActive = { true }; env.activate = { _ in }; env.board = board
        env.key = { key, _, _ in
            events.append(key)
            if key == 9 {
                let previousPrompt = CLIPromptPolicy.prompt(screen:screen,binding:binding,origin:verifiedOrigin)?.text ?? ""
                let inserted = pasteMode == "collapsed" ? "[Pasted text #1 +120 lines]" : (pasteMode == "append" ? previousPrompt : "") + board.string(forType:.string)!
                screen = verifiedEmpty.replacingOccurrences(of:"❯ ",with:"❯ "+inserted.replacingOccurrences(of:"\n",with:"\n  "))
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
        let sent = try await driver.deliver("Hello.",to:bound,autoSend:true,current:{current})
        check(sent == .sendKeyPressed && events == [9,36],"exact single-line paste sends once using the frozen session")
        check(board.string(forType:.string)=="Original clipboard","a successful CLI paste restores the previous clipboard")
        screen=verifiedEmpty; events=[]
        let inserted = try await driver.deliver("Hello.",to:bound,autoSend:false,current:{current})
        check(inserted == .inserted && events == [9],"turning off automatic send still pastes once without Return")
        events=[]
        do { _ = try await driver.deliver("Hello.",to:bound,autoSend:false,current:{current});check(false,"repeated fill rejected") }
        catch {check(events.isEmpty,"an unchanged received translation cannot be pasted a second time")}
        screen=verifiedEmpty; events=[]
        let multiple = try await driver.deliver("First line.\nSecond line.",to:bound,autoSend:true,current:{current})
        check(multiple == .inserted && events == [9],"multiline delivery is preserved without guessing Enter mode")
        screen=verifiedEmpty; events=[]; pasteMode="collapsed"
        let collapse = try await driver.deliver(String(repeating:"long ",count:300),to:bound,autoSend:true,current:{current})
        check(collapse == .collapsed && events == [9],"a collapsed long paste is never retried or automatically sent")
        events=[]
        do { _ = try await driver.deliver(String(repeating:"long ",count:300),to:bound,autoSend:true,current:{current});check(false,"repeated collapsed fill rejected") }
        catch {check(events.isEmpty,"an unchanged collapsed paste cannot be inserted again by a later fill action")}
        screen=verifiedEmpty; events=[]; pasteMode="redraw"
        do {
            let redraw=try await driver.deliver("Hello.",to:bound,autoSend:true,current:{current})
            check(redraw == .sendKeyPressed && events == [9,36],"temporary terminal redraw waits for exact input instead of abandoning the paste")
        } catch {check(false,"temporary terminal redraw must recover within its receipt window")}
        for mode in ["exit","switch","retire"] {
            screen=verifiedEmpty; events=[]; pasteMode=mode; live=true; focused=true; current=true; redrawReads=0
            do { _ = try await driver.deliver("Hello.",to:bound,autoSend:true,current:{current}); check(false,"after-paste \(mode) rejected") }
            catch { check(events == [9],"after-paste \(mode) blocks Return and duplicate paste") }
        }
        screen=verifiedEmpty; events=[]; pasteMode="plain"; live=true; focused=true; current=true; replaceBoard=true
        _ = try await driver.deliver("Hello.",to:bound,autoSend:false,current:{current})
        check(board.string(forType:.string)=="User's newer clipboard","a newer user clipboard is not overwritten by restoration")
        let suggestion=verifiedEmpty.replacingOccurrences(of:"❯ ",with:"❯ Try explaining this code")
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
            check(result == .unconfirmed && events == [9],"text appended to actual input is not retried or submitted as an exact translation")
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
        check(model.hasTarget && model.isCLIConnection && model.bridge.selected==binding,"shortcut surface pairs only the matching strong footer with its live CLI report")
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
        screen=verifiedEmpty; events=[]
        var delayed:CheckedContinuation<String,Error>?
        model.testTranslation={_ in try await withCheckedThrowingContinuation {delayed=$0} };model.input="你好";model.begin(insert:true)
        while delayed==nil { try await Task.sleep(for:.milliseconds(5)) }
        model.bridge.select("cli-"+String(repeating:"b",count:64))
        delayed?.resume(returning:"Hello.");delayed=nil
        while model.busy { try await Task.sleep(for:.milliseconds(10)) }
        check(events.isEmpty && model.output=="Hello." && model.input=="你好","switching selected CLI sessions while translating cannot send the late result")
        check(!model.hasTarget && model.replies.watching,"a different selected source stays readable without inheriting another pane")
        screen=verifiedEmpty.replacingOccurrences(of:validTag,with:"waiting-for-footer")
        model.connectCapturedTarget(captured)
        try await client("read-only")
        model.bridge.select(binding)
        check(!model.hasTarget,"a captured surface cannot send before a verifiable CLI report and matching current footer")
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
