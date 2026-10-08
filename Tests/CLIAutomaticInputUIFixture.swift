import AppKit
import SwiftUI
import ApplicationServices
import CryptoKit

// Standalone, synthetic native surface. Never starts, controls or impersonates
// a real terminal. Only this test injects process liveness; AX and keys are real.
@MainActor final class SyntheticCLITextView: NSTextView {
    var footer = ""
    var collapsed = false
    var pasted = ""
    var pasteCount = 0, returnCount = 0
    var base: String { "Claude Code synthetic surface\nPrevious synthetic answer.\n────────────────\n❯ \n────────────────\n" + footer + "\n? for shortcuts" }
    func reset() { pasted="";pasteCount=0;returnCount=0;string=base;setSelectedRange(.init(location:0,length:0)) }
    override func paste(_ sender: Any?) {
        pasteCount += 1; pasted = NSPasteboard.general.string(forType:.string) ?? ""
        let shown = collapsed ? "[Pasted text #1 +120 lines]" : pasted.replacingOccurrences(of:"\n",with:"\n  ")
        string = base.replacingOccurrences(of:"❯ ",with:"❯ "+shown)
    }
    override func keyDown(with event:NSEvent) {
        if event.keyCode == 36 {
            returnCount += 1
            string = "Synthetic submitted: \(pasted)\n" + base
        } else { super.keyDown(with:event) }
    }
}

@MainActor final class CLIAutomaticInputFixture: NSObject, NSApplicationDelegate {
    var terminal: NSWindow!, panel: NSWindow!, screen: SyntheticCLITextView!
    var model:TranslatorModel!, usage = ClaudeUsageMonitor()
    let binding = "cli-"+String(repeating:"a",count:64)
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
        screen.reset();scroll.documentView=screen;terminal.contentView=scroll
        var env=CLITargetBridge.Environment();env.live={_ in true}
        env.focused={surface,front in front ? CLITargetBridge.focused(surface,true) : true}
        // In production this activates another app and restores its window.
        // The fixture has two windows in one app, so restore its saved window.
        env.activate={ [weak self] _ in NSApp.activate(ignoringOtherApps:true);self?.terminal.makeKeyAndOrderFront(nil);self?.terminal.makeFirstResponder(self?.screen) }
        model=TranslatorModel(permissionCheck:{true},remoteKeyRead:{_ in "synthetic-key"},cliDelivery:CLITargetBridge(environment:env))
        let root=Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
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
                Button("短文场景"){self.prepare("你好",foreign:"Hello.",collapsed:false)}
                Button("多行场景"){self.prepare("第一行。\n第二行。",foreign:"First line.\nSecond line.",collapsed:false)}
                Button("折叠场景"){self.prepare(String(repeating:"长内容。",count:100),foreign:String(repeating:"Long text. ",count:100),collapsed:true)}
            }.padding(6)
            MainView(model:model,usage:usage)
        })
        terminal.makeKeyAndOrderFront(nil);panel.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    @objc func showPanel(){panel.makeKeyAndOrderFront(nil)}
    func prepare(_ chinese:String,foreign:String,collapsed:Bool){ screen.collapsed=collapsed;screen.reset();model.testTranslation={_ in foreign};model.input=chinese;panel.makeKeyAndOrderFront(nil) }
    func connect(){
        terminal.makeKeyAndOrderFront(nil);terminal.makeFirstResponder(screen)
        DispatchQueue.main.async { [weak self] in
            guard let self else{return}
            let ax=AXUIElementCreateApplication(getpid())
            guard let focus=TargetBridge.elementAttribute(ax,kAXFocusedUIElementAttribute),let window=TargetBridge.elementAttribute(ax,kAXFocusedWindowAttribute) else {self.model.report("模拟表面未提供焦点",error:true);return}
            let surface=CLITargetBridge.Surface(app:.current,window:window,focus:focus,element:focus)
            self.model.cliCapture={surface}
            self.model.connectCapturedTarget(.init(app:.current,element:focus,window:window,value:self.screen.string,selection:nil,conversation:nil,identity:.init(role:"AXTextArea",identifier:nil,description:nil,placeholder:nil)))
            self.panel.makeKeyAndOrderFront(nil)

        }
    }
    func applicationWillTerminate(_ notification:Notification){model.bridge.stop();model.cancel();model.stopPermissionMonitoring();usage.stop()}
}
@main struct CLIAutomaticFixtureApp {
    @MainActor static func main(){let app=NSApplication.shared;app.setActivationPolicy(.regular);let delegate=CLIAutomaticInputFixture();app.delegate=delegate;withExtendedLifetime(delegate){app.run()}}
}
