import AppKit
import ApplicationServices

@main struct NativeWebUsageTests {
    static var checks = 0, failures = 0
    @MainActor static func check(_ value: Bool, _ label: String) {
        checks += 1; if !value { failures += 1 }; print((value ? "PASS: " : "FAIL: ") + label)
    }
    @MainActor static func main() async throws {
        let window = WebUsageSelection(app:.current, window:AXUIElementCreateApplication(getpid()), input:nil)
        var front = true, available = true, actions: [String] = [], identityCalls = 0, different = false, restoreFails = false
        let a = try WebUsagePage.identity(["a@example.test"]), b = try WebUsagePage.identity(["b@example.test"])
        var pending: CheckedContinuation<ClaudeUsageSnapshot, Error>?
        let environment = NativeWebUsage.Environment(discover:{ [window] }, available:{ _ in available }, foreground:{ _ in front }, activate:{ _ in actions.append("activate");front=true }, begin:{ _ in .init(url:"https://claude.ai/new", wasUsage:false) }, account:{ _ in
            actions.append("account");identityCalls += 1;return different && identityCalls.isMultiple(of:2) ? b : a
        }, quota:{ _ in
            actions.append("usage");return .init(fiveHour:.init(usedPercentage:12,resetsAt:nil),sevenDay:.init(usedPercentage:34,resetsAt:nil),observedAt:Date())
        }, restore:{ _,_ in actions.append("restore");if restoreFails {throw BridgeError.message("Synthetic restore failure")} })
        let reader = NativeWebUsage(environment:environment)
        var reports: [UsageEvidence] = [], invalid: [UsageAccountObservation] = []
        reader.onEvidence={reports.append($0)};reader.onInvalid={invalid.append($0)}
        reader.bind(window)
        try await reader.read(explicit:false)
        check(reports.count == 1 && actions == ["account","usage","account","restore"], "same-window identity sandwich publishes only after restoration")
        check(reports.first?.identity == a && reports.first?.source == .usagePage, "native report contains masked verified Web account")
        reader.canRead={false};actions=[]
        do { try await reader.read(explicit:true);check(false,"message delivery and quota navigation cannot overlap") } catch {check(actions.isEmpty,"message delivery and quota navigation cannot overlap")}
        reader.canRead={true}
        front=false;actions=[]
        do {try await reader.read(explicit:false);check(false,"background automatic request is refused")} catch {check(true,"background automatic request is refused")}
        check(actions.isEmpty && reports.count == 1, "background request never activates or navigates the browser")
        try await reader.read(explicit:true)
        check(actions.first == "activate" && reports.count == 2, "only explicit reading can restore the selected physical window")
        different=true;actions=[]
        do {try await reader.read(explicit:false);check(false,"account change during reading is rejected")} catch {check(true,"account change during reading is rejected")}
        check(reports.count == 2 && invalid.last?.identity == nil, "account mismatch hides old quota without publishing")
        different=false;restoreFails=true
        do {try await reader.read(explicit:false);check(false,"failed page restoration does not publish")} catch {check(true,"failed page restoration does not publish")}
        check(reports.count == 2, "restore failure cannot turn a quota candidate into a final report")
        restoreFails=false;available=false;actions=[]
        do {try await reader.read(explicit:true);check(false,"closed window is rejected")} catch {check(true,"closed window is rejected")}
        check(actions.isEmpty, "a closed window never redirects reading to another window")
        available=true;reader.unbind()
        check(!reader.hasSelectedTarget && reader.binding.isEmpty, "disconnect clears only the quota target")
        var ambiguous = environment;ambiguous.discover={ [window,window] }
        let multiple = NativeWebUsage(environment:ambiguous)
        do {try await multiple.readOpenUsage();check(false,"multiple Usage windows are not guessed")} catch {check(true,"multiple Usage windows are not guessed")}
        check(!multiple.hasSelectedTarget, "ambiguous discovery creates no quota binding")
        var failedQuota = environment;failedQuota.quota={_ in throw BridgeError.message("Synthetic Usage not ready")}
        let staged = NativeWebUsage(environment:failedQuota);staged.bind(window);actions=[]
        do {try await staged.read(explicit:true);check(false,"quota failure identifies its stage")}
        catch {check(staged.status.contains("读取 Usage") && actions.last == "restore", "quota failure identifies its stage and still restores the original page")}
        var slow = environment;slow.quota={ _ in try await withCheckedThrowingContinuation {pending=$0} }
        let retired = NativeWebUsage(environment:slow);var lateReports=0
        retired.onEvidence={_ in lateReports += 1};retired.bind(window)
        let old = Task {try await retired.read(explicit:false)}
        while pending == nil {await Task.yield()}
        retired.unbind();pending?.resume(returning:.init(fiveHour:nil,sevenDay:.init(usedPercentage:99,resetsAt:nil),observedAt:Date()))
        _ = try? await old.value
        check(lateReports == 0 && !retired.busy, "late quota from a retired binding never restores old state")
        var changed = environment, currentAccount = a
        changed.account={_ in currentAccount}
        let switches = NativeWebUsage(environment:changed);var changedReports: [UsageEvidence] = []
        switches.onEvidence={changedReports.append($0)};switches.bind(window)
        try await switches.read(explicit:true);currentAccount=b
        try await switches.read(explicit:true);currentAccount=a
        try await switches.read(explicit:true)
        check(Set(changedReports.map(\.epoch)).count == 3 && changedReports.map(\.sequence) == [1,2,3], "A to B to A uses new account epochs and monotonic sequences")
        var lost = environment;actions=[];front=true
        lost.quota={_ in front=false;return .init(fiveHour:nil,sevenDay:.init(usedPercentage:13,resetsAt:nil),observedAt:Date())}
        let interrupted = NativeWebUsage(environment:lost);var interruptionReports=0
        interrupted.onEvidence={_ in interruptionReports += 1};interrupted.bind(window)
        do {try await interrupted.read(explicit:false);check(false,"focus loss cancels reading")} catch {check(true,"focus loss cancels reading")}
        check(interruptionReports == 0 && !actions.contains("activate") && !actions.contains("restore"), "focus loss never restores or activates a background window")
        front=true;actions=[]
        do {try await interrupted.read(explicit:false);check(false,"interrupted restoration pauses automatic navigation")} catch {check(actions.isEmpty,"interrupted restoration pauses automatic navigation")}

        let prefs = UserDefaults(suiteName:"NativeWebUsageTests-" + UUID().uuidString)!
        let monitor = ClaudeUsageMonitor(settings:prefs,enabled:{false})
        monitor.follow(channel:.web,binding:"web-native-test")
        monitor.receive(.init(source:.usagePage,binding:"web-native-test",snapshot:.init(fiveHour:nil,sevenDay:.init(usedPercentage:34,resetsAt:nil),observedAt:Date()),identity:a,epoch:"test",sequence:1))
        var started=false, finished=false
        monitor.requestReport={_,_,_ in
            monitor.beginVisibleRead(binding:"web-native-test");started=true
            try await Task.sleep(for:.milliseconds(10));finished=true
            monitor.receive(.init(source:.usagePage,binding:"web-native-test",snapshot:.init(fiveHour:nil,sevenDay:.init(usedPercentage:35,resetsAt:nil),observedAt:Date()),identity:a,epoch:"test",sequence:2))
        }
        monitor.acquire(.web,binding:"web-native-test")
        while !started {await Task.yield()}
        check(monitor.acquiring && monitor.snapshot == nil,"beginning a native read hides old quota without cancelling its acquisition")
        while !finished {await Task.yield()}
        check(!monitor.acquiring && monitor.snapshot?.sevenDay?.usedPercentage == 35,"fresh quota completes the original acquisition")
        monitor.stop()
        let reconnect = ClaudeUsageMonitor(settings:prefs,enabled:{false})
        let attached = NativeWebUsage(environment:environment)
        attached.onBound={reconnect.follow(channel:.web,binding:$0)}
        attached.onReading={reconnect.beginVisibleRead(binding:$0)}
        attached.onEvidence={reconnect.receive($0)}
        attached.bind(window);try await attached.read(explicit:false)
        reconnect.removeSession={preconditionFailure("Web disconnect must never remove a saved manual session")}
        await reconnect.disconnectAsync()
        try await attached.read(explicit:true)
        check(reconnect.snapshot?.sevenDay?.usedPercentage == 34,"explicit read reconnects the same quota window after disconnect without rebinding its sender")
        reconnect.stop()
        let replies = ReplyMonitor();replies.watching=true;replies.status="Synthetic reply reading"
        replies.setCapturePaused(true)
        replies.handleReadFailure(ReplyReadStopped(message:"Usage modal temporarily hides the conversation"))
        check(replies.watching && replies.status == "Synthetic reply reading","a Usage modal cannot stop or replace conversation reading")
        replies.setCapturePaused(false)
        replies.handleReadFailure(ReplyReadPending(message:"Synthetic retry"))
        check(replies.watching && replies.status.contains("Synthetic retry"),"normal conversation capture resumes after Usage restoration")
        replies.stop()
        print("\(checks) native Web reader checks; \(failures) failed")
        if failures > 0 {exit(1)}
    }
}
