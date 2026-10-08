import AppKit
import SwiftUI
import ApplicationServices
import CryptoKit

// Standalone, synthetic native surface. Never starts, controls or impersonates
// a real terminal. AX, clipboard, native paste handling and system translation
// are real; process/focus identity and cross-process transport are synthetic.
@MainActor final class SyntheticCLITextView: NSTextView {
    var footer = ""
    var collapsed = false
    var blankRows = 0
    var suggestion = ""
    var wrapColumn = 0
    var footerWrapped = false
    var inputHint = "? for shortcuts"
    var checkpointURL: URL?
    var pasted = ""
    var pasteCount = 0, returnCount = 0
    var base: String { "Claude Code synthetic surface\nPrevious synthetic answer.\n────────────────\n❯ " + suggestion + "\n────────────────\n" + (footerWrapped ? footer.replacingOccurrences(of:" · 输入 ",with:" · 输\n入 ") : footer) + "\n" + inputHint + String(repeating:"\n    ",count:blankRows) }
    func checkpoint() {
        guard let checkpointURL, let data=try? JSONSerialization.data(withJSONObject:["synthetic":true,"pasteCount":pasteCount,"returnCount":returnCount,"pastedCharacters":pasted.count],options:[.sortedKeys]) else{return}
        try? data.write(to:checkpointURL,options:.atomic)
    }
    func reset() { pasted="";pasteCount=0;returnCount=0;string=base;setSelectedRange(.init(location:0,length:0));checkpoint() }
    override func paste(_ sender: Any?) {
        pasteCount += 1; pasted = NSPasteboard.general.string(forType:.string) ?? ""
        var shown = collapsed ? "[Pasted text #1 +120 lines]" : pasted.replacingOccurrences(of:"\n",with:"\n  ")
        if wrapColumn > 0 && !collapsed {
            let characters=Array(pasted)
            shown=stride(from:0,to:characters.count,by:wrapColumn).map {String(characters[$0..<min(characters.count,$0+wrapColumn)])}.joined(separator:"\n  ")
        }
        string = base.replacingOccurrences(of:"❯ "+suggestion,with:"❯ "+shown)
        checkpoint()
    }
    override func keyDown(with event:NSEvent) {
        if event.keyCode == 36 {
            returnCount += 1
            string = "Synthetic submitted: \(pasted)\n" + base
            checkpoint()
        } else { super.keyDown(with:event) }
    }
}

@MainActor final class CLIAutomaticInputFixture: NSObject, NSApplicationDelegate {
    var terminal: NSWindow!, panel: NSWindow!, screen: SyntheticCLITextView!
    var model:TranslatorModel!, usage = ClaudeUsageMonitor()
    let binding = "cli-"+String(repeating:"a",count:64)
    var fullFooter = ""
    func applicationDidFinishLaunching(_ notification:Notification) {
        precondition(CompanionPreferences.simulated)
        AppMenus.install()
        let nav=NSMenuItem(title:"测试窗口",action:nil,keyEquivalent:"");let menu=NSMenu(title:"测试窗口")
        let item=NSMenuItem(title:"显示伴侣面板",action:#selector(showPanel),keyEquivalent:"b");item.target=self
        menu.addItem(item);nav.submenu=menu;NSApp.mainMenu?.addItem(nav)
        terminal=NSWindow(contentRect:.init(x:40,y:250,width:630,height:410),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        terminal.title="CLI 自动输入 · 本机模拟目标"
        let scroll=NSScrollView(frame:terminal.contentView!.bounds);scroll.autoresizingMask=[.width,.height];scroll.hasVerticalScroller=true
        screen=SyntheticCLITextView(frame:scroll.bounds);screen.isEditable=true;screen.isRichText=false
        screen.font = .monospacedSystemFont(ofSize:13,weight:.regular); screen.autoresizingMask=[.width,.height]
        screen.textContainer?.widthTracksTextView=true
        let started="Mon Oct 5 11:59:00 2026"
        let tag=String(SHA256.hash(data:Data((binding+"\0"+"40"+"\0"+started).utf8)).map {String(format:"%02x",$0)}.joined().prefix(20))
        screen.footer="A畜伴侣 CLI · aaaaaa · Synthetic a · 输入 "+tag
        fullFooter=screen.footer
        screen.reset();scroll.documentView=screen;terminal.contentView=scroll
        var env=CLITargetBridge.Environment();env.live={_ in true};env.trusted={true}
        // UI automation does not make this test app the system frontmost app.
        // Model that boundary explicitly; all events still target this PID.
        // Production focus/foreground guards are exercised by delivery tests.
        env.focused={surface,_ in surface.app.processIdentifier == getpid()}
        // In production this activates another app and restores its window.
        // The fixture has two windows in one app, so restore its saved window.
        env.activate={ [weak self] _ in NSApp.activate(ignoringOtherApps:true);self?.terminal.makeKeyAndOrderFront(nil);self?.terminal.makeFirstResponder(self?.screen) }
        // Exercise native paste/Return handling only inside this test app.
        // Posting cross-process CGEvents requires a separate TCC grant for a
        // fixture identity; no extra user grant is needed for own Cocoa events.
        env.key={ [weak self] key,flags,pid in
            guard let self,pid==getpid(),[9,36].contains(key) else {throw BridgeError.message("模拟事件目标不是自身")}
            // CUA keeps this app in the background. Cmd+V's global menu route
            // therefore cannot stand in for a foreground cross-process key.
            // Exercise the same native paste action in this process directly.
            if key == 9 {
                guard self.terminal.firstResponder === self.screen else {throw BridgeError.message("模拟输入位置未恢复")}
                guard NSApp.sendAction(#selector(NSText.paste(_:)),to:self.screen,from:nil) else {throw BridgeError.message("模拟粘贴动作失败")}
                return
            }
            let characters=key==9 ? "v":"\r"
            guard let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags.contains(.maskCommand) ? .command:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:self.terminal.windowNumber,context:nil,characters:characters,charactersIgnoringModifiers:characters,isARepeat:false,keyCode:key) else {throw BridgeError.message("模拟事件无法创建")}
            NSApp.postEvent(event,atStart:false)
        }
        model=TranslatorModel(permissionCheck:{true},remoteKeyRead:{_ in "synthetic-key"},cliDelivery:CLITargetBridge(environment:env))
        let root=Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let results=root.appendingPathComponent(".build/cli-auto-input")
        try? FileManager.default.createDirectory(at:results,withIntermediateDirectories:true)
        screen.checkpointURL=results.appendingPathComponent("native-events.json")
        model.cliEntryRequest={path in
            let code=try await Task.detached {
                let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/bin/python3");p.currentDirectoryURL=root;p.arguments=["Tests/CLIDeliveryClient.py",path]
                try p.run();p.waitUntilExit();return p.terminationStatus
            }.value
            if code != 0 {throw BridgeError.message("模拟报告失败（退出码 \(code)）")}
        };model.engine="gemini";model.language = .english;model.autoSend=true
        model.testTranslation={_ in "Hello."};model.replies.testTranslation={_ in "完整的模拟回复。"}
        panel=NSWindow(contentRect:.init(x:700,y:130,width:610,height:820),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        panel.title="CLI 自动输入 · 伴侣模拟"
        panel.contentView=NSHostingView(rootView:VStack(spacing:0){
            HStack{
                Button("连接模拟输入区"){self.connect()}
                Button("首次连接（标记晚到）"){self.connectWithDelayedFooter()}
                Button("短文场景"){self.prepare("你好",foreign:"Hello.",collapsed:false)}
                Button("多行场景"){self.prepare("第一行。\n第二行。",foreign:"First line.\nSecond line.",collapsed:false)}
                Button("折叠场景"){self.prepare(String(repeating:"长内容。",count:100),foreign:String(repeating:"Long text. ",count:100),collapsed:true)}
            }.padding(6)
            Button("推荐提示场景"){
                self.screen.footer=self.fullFooter;self.screen.suggestion="Try explaining this code";self.screen.blankRows=40
                self.prepare("你好",foreign:"Hello.",collapsed:false);self.connect()
            }.padding(.bottom,6)
            HStack {
                Button("系统自动发送场景") {
                    self.model.cancel();self.model.engine="apple";self.model.testFallback=nil
                    self.screen.suggestion="Try explaining this code"
                    self.prepare("你好",foreign:"Hello.",collapsed:false);self.connect()
                }
                Button("Gemini失败备用发送场景") {
                    self.model.cancel();self.model.engine="gemini";self.model.testFallback=nil
                    self.screen.suggestion="Try explaining this code"
                    self.prepare("你好",foreign:"Hello.",collapsed:false)
                    self.model.testTranslation={_ in throw BridgeError.message("Gemini 模拟503。")};self.connect()
                }
            }.padding(.bottom,6)
            HStack {
                Button("窄终端换行场景") {
                    self.terminal.setContentSize(.init(width:630,height:690))
                    self.screen.wrapColumn=10;self.screen.footerWrapped=true
                    self.prepare(String(repeating:"检验完整输入。",count:20),foreign:String(repeating:"abcdefghij",count:20)+"🙂",collapsed:false);self.connect()
                }
                Button("选择提示场景") {
                    self.screen.string="Do you want to proceed?\n  python3 /synthetic/test.py\n❯ 1. Yes\n  2. Yes, and don't ask again\n  3. No\nEnter to confirm · Esc to cancel"
                }
                Button("运行提示场景") {self.screen.string="✻ Thinking… (5s · ↓ 20 tokens)"}
                Button("截图中的CLI布局") {
                    self.screen.inputHint="⏵⏵ auto mode on (shift+tab to cycle) · ← for agents"
                    self.screen.suggestion="Try create a utility script"
                    self.prepare("你好",foreign:"Hello.",collapsed:false);self.connect()
                }
            }.padding(.bottom,6)
            HStack {
                Button("取消质量审核场景") {
                    self.screen.inputHint="⏵⏵ auto mode on (shift+tab to cycle) · ← for agents"
                    self.screen.suggestion="Try create a utility script"
                    self.model.engine="gemini";self.model.testFallback=nil
                    self.prepare("请运行20次。",foreign:"Please run 30 times.",collapsed:false);self.connect()
                }
                Button("备用译文无需审核场景") {
                    self.model.engine="gemini"
                    self.prepare("结果可靠吗？",foreign:"The result is reliable.",collapsed:false)
                    self.model.testTranslation={_ in throw BridgeError.message("Gemini 模拟503。")}
                    self.model.testFallback={_ in "The result is reliable."};self.connect()
                }
            }.padding(.bottom,6)
            MainView(model:model,usage:usage)
        })
        terminal.makeKeyAndOrderFront(nil);panel.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    @objc func showPanel(){NSApp.activate(ignoringOtherApps:true);panel.makeKeyAndOrderFront(nil)}
    func prepare(_ chinese:String,foreign:String,collapsed:Bool){ screen.collapsed=collapsed;screen.reset();model.testTranslation={_ in foreign};model.input=chinese;NSApp.activate(ignoringOtherApps:true);panel.makeKeyAndOrderFront(nil) }
    func connect(){
        NSApp.activate(ignoringOtherApps:true)
        terminal.makeKeyAndOrderFront(nil);terminal.makeFirstResponder(screen)
        DispatchQueue.main.async { [weak self] in
            guard let self else{return}
            let ax=AXUIElementCreateApplication(getpid())
            guard let focus=TargetBridge.elementAttribute(ax,kAXFocusedUIElementAttribute),let window=TargetBridge.elementAttribute(ax,kAXFocusedWindowAttribute) else {self.model.report("模拟表面未提供焦点",error:true);return}
            self.model.cliCapture={try CLITargetBridge.captureSurface(app:.current,focus:focus,window:window)}
            self.model.connectCapturedTarget(.init(app:.current,element:focus,window:window,value:self.screen.string,selection:nil,conversation:nil,identity:.init(role:"AXTextArea",identifier:nil,description:nil,placeholder:nil)))
            self.panel.makeKeyAndOrderFront(nil)

        }
    }
    func connectWithDelayedFooter(){
        model.bridge.stop();screen.footer="";screen.suggestion="";screen.blankRows=40;screen.collapsed=false;screen.reset()
        model.testTranslation={_ in "Hello."};model.input="你好"
        connect()
        DispatchQueue.main.asyncAfter(deadline:.now()+0.8){ [weak self] in
            guard let self else{return};self.screen.footer=self.fullFooter;self.screen.reset()
        }
    }
    func applicationWillTerminate(_ notification:Notification){model.bridge.stop();model.cancel();model.stopPermissionMonitoring();usage.stop()}
}
@main struct CLIAutomaticFixtureApp {
    @MainActor static func main(){let app=NSApplication.shared;app.setActivationPolicy(.regular);let delegate=CLIAutomaticInputFixture();app.delegate=delegate;withExtendedLifetime(delegate){app.run()}}
}
