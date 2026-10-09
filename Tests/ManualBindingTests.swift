import AppKit
import ApplicationServices
import CryptoKit

@main struct ManualBindingTests {
    static var count = 0, failures = 0
    @MainActor static func check(_ value: Bool, _ label: String) {
        count += 1; if !value { failures += 1 }; print((value ? "PASS: " : "FAIL: ") + label)
    }
    @MainActor static func main() async throws {
        setvbuf(stdout, nil, _IONBF, 0); _ = NSApplication.shared
        let session="cli-"+String(repeating:"a",count:64), started="Mon Oct 5 11:59:00 2026"
        let tag=String(SHA256.hash(data:Data((session+"\0"+"40"+"\0"+started).utf8)).map {String(format:"%02x",$0)}.joined().prefix(20))
        let origin=CLIDeliveryOrigin(pid:40,tty:"ttys003",started:started,tag:tag)
        let own=NSRunningApplication.current, element=AXUIElementCreateApplication(getpid())
        let surface=CLITargetBridge.Surface(app:own,window:element,focus:element,element:element)
        let known="Claude Code\n────────\n❯ \n────────\nA畜伴侣 CLI · aaaaaa · Synthetic · 输入 "+tag+"\n? for shortcuts"
        let board=NSPasteboard(name:.init("achu-manual-"+UUID().uuidString));defer {board.releaseGlobally()}
        var screen:String?=known, alive=true, focused=true, current=true, events:[CGKeyCode]=[]
        var env=CLITargetBridge.Environment();env.trusted={true};env.alive={_ in alive};env.focused={_,_ in focused}
        env.screen={_ in screen};env.live={_ in true};env.activate={_ in focused=true};env.key={code,_,_ in events.append(code)};env.board=board
        let driver=CLITargetBridge(environment:env)
        screen="Unrecognized layout and recommended text"
        do { _=try driver.bind(surface:surface,session:session,origin:origin);check(true,"manual input binding does not require a recognized layout") }
        catch {check(false,"manual input binding does not require a recognized layout")}
        screen=known
        let bound=try driver.bind(surface:surface,session:session,origin:origin)
        for (layout,text) in [(nil,"Hello."),("Unknown hint","Hello."),("[Pasted text #1 +120 lines]","First line.\nSecond line."),("Do you want to proceed?\n1. Yes\n2. No","Please explain.")] as [(String?,String)] {
            screen=layout;events=[];focused=false
            do {
                let result=try await driver.deliver(text,to:bound,autoSend:true,current:{current})
                check(result == .sendKeyPressed && events == [9,36],"the chosen input receives one paste and Return without interpreting its contents")
            } catch {check(false,"the chosen input receives one paste and Return without interpreting its contents")}
        }
        screen=nil;events=[]
        do {
            let result=try await driver.deliver("Hello.",to:bound,autoSend:false,current:{current})
            check(result == .inserted && events == [9],"the user's disabled-send preference is retained")
        } catch {check(false,"the user's disabled-send preference is retained")}
        current=false;events=[]
        do {_=try await driver.deliver("Hello.",to:bound,autoSend:true,current:{current});check(false,"a replaced connection retires pending input")}
        catch {check(events.isEmpty,"a replaced connection retires pending input")}
        current=true;alive=false;events=[]
        do {_=try await driver.deliver("Hello.",to:bound,autoSend:true,current:{current});check(false,"a closed selected window cannot receive input")}
        catch {check(events.isEmpty,"a closed selected window cannot receive input")}
        alive=true;screen=nil
        let model=TranslatorModel(permissionCheck:{true},remoteKeyRead:{_ in "synthetic-key"},cliDelivery:driver)
        defer {model.bridge.stop();model.cancel();model.stopPermissionMonitoring()}
        model.cliCapture={surface};model.cliEntryRequest={_ in}
        let captured=TargetBridge.Target(app:own,element:element,window:element,value:nil,selection:nil,conversation:nil,identity:.init(role:"AXGroup",identifier:nil,description:nil,placeholder:nil))
        model.connectCapturedTarget(captured)
        check(model.hasTarget && model.isCLIConnection && !model.showCLIPicker,"the shortcut immediately retains the manually chosen input without a read report")
        model.engine="gemini";model.language = .english;model.autoSend=true;model.testTranslation={_ in "Hello."};model.input="你好";events=[]
        model.begin(insert:true)
        let end=ContinuousClock.now.advanced(by:.seconds(3))
        while model.busy,ContinuousClock.now<end {try await Task.sleep(for:.milliseconds(5))}
        check(!model.busy && model.output=="Hello." && model.input.isEmpty && events==[9,36],"reply and quota discovery never gate outgoing translation and sending")
        model.bridge.stop()
        check(model.hasTarget,"stopping reply reading keeps the manually chosen sender")
        let web=TargetBridge.Target(app:own,element:element,window:element,value:"Changed unrelated contents",selection:nil,conversation:"https://claude.ai/chat/synthetic",identity:.init(role:"AXGroup",identifier:nil,description:nil,placeholder:nil))
        model.connectCapturedTarget(web)
        check(model.hasTarget && !model.isCLIConnection,"native Web routing pins input immediately without waiting for reply capture")
        events=[];model.input="你好";model.begin(insert:true)
        while model.busy {try await Task.sleep(for:.milliseconds(5))}
        check(events==[9,36] && model.input.isEmpty,"the native route uses the same direct sender without inspecting value or caret")
        var pending:CheckedContinuation<String,Error>?
        model.testTranslation={_ in try await withCheckedThrowingContinuation {pending=$0}}
        model.input="保留当前草稿";events=[];model.begin(insert:true)
        while pending==nil {try await Task.sleep(for:.milliseconds(2))}
        model.connectCapturedTarget(web)
        pending?.resume(returning:"Retain the draft.");pending=nil
        while model.busy {try await Task.sleep(for:.milliseconds(5))}
        check(events.isEmpty && model.input=="保留当前草稿" && model.output=="Retain the draft.","reconnecting retires the old job instead of redirecting it to a new input lease")
        model.replies.stop()

        // Two synthetic anchors in one app: restore only the one selected by
        // the user. Missing values, layouts and URLs cannot enter this API.
        let other=AXUIElementCreateSystemWide()
        let pinned=ManualInputDelivery.Location(app:own,window:element,input:element)
        var actualWindow=other,actualInput=other,available=true,permitted=true,restores=0
        var pasteFails=false,returnFails=false
        var shared=ManualInputDelivery.Environment()
        shared.trusted={permitted};shared.available={_ in available};shared.board=board
        shared.restore={location in restores+=1;actualWindow=location.window;actualInput=location.input}
        shared.focused={location in CFEqual(location.window,actualWindow) && CFEqual(location.input,actualInput)}
        shared.key={code,_,pid in
            check(pid==getpid(),"synthetic events remain in this test process")
            events.append(code)
            if code==9 && pasteFails {throw BridgeError.message("Synthetic paste failure")}
            if code==36 && returnFails {throw BridgeError.message("Synthetic Return failure")}
        }
        let common=ManualInputDelivery(environment:shared),lease=try common.bind(pinned)
        for channel in ["Desktop","Web","CLI"] {
            actualWindow=other;actualInput=other;events=[]
            let result=try await common.deliver("First line.\nSecond line.",to:lease,autoSend:true,current:{true})
            check(result == .sendKeyPressed && events==[9,36] && CFEqual(actualWindow,element) && CFEqual(actualInput,element),channel+" restores the exact selected window and input before paste and Return")
        }
        check(restores==3,"each channel restores its saved target once without searching another window")
        events=[];pasteFails=true
        do {_=try await common.deliver("Hello.",to:lease,autoSend:true,current:{true});check(false,"failed paste does not send Return")}
        catch {check(events==[9],"failed paste does not send Return")}
        pasteFails=false;returnFails=true;events=[]
        let partial=try await common.deliver("Hello.",to:lease,autoSend:true,current:{true})
        if case .submitFailed = partial {check(events==[9,36],"failed Return reports partial completion without another paste")}
        else {check(false,"failed Return reports partial completion without another paste")}
        returnFails=false;permitted=false;events=[]
        do {_=try await common.deliver("Hello.",to:lease,autoSend:true,current:{true});check(false,"missing permission preserves the selected target without keys")}
        catch {check(events.isEmpty,"missing permission preserves the selected target without keys")}
        permitted=true;available=false;events=[]
        do {_=try await common.deliver("Hello.",to:lease,autoSend:true,current:{true});check(false,"a vanished selected input never redirects to another window")}
        catch {check(events.isEmpty,"a vanished selected input never redirects to another window")}
        print("\(count) manual input binding checks; \(failures) failed")
        if failures>0 {exit(1)}
    }
}
