import AppKit
import Foundation
import CoreFoundation
import SwiftUI

/// Manages the bundled quota-only module; browser credentials never enter it.
@MainActor final class ManagedWebUsage: ObservableObject {
    @Published private(set) var status = "连接网页时由伴侣准备接口，首次仅需确认授权"
    @Published private(set) var available = false
    @Published private(set) var authorized = false
    @Published private(set) var connecting = false
    @Published private(set) var binding = ""
    @Published private(set) var hasSelectedTarget = false
    var sourceBrowser: String?
    var onBound: (String) -> Void = { _ in }
    var onEvidence: (UsageEvidence) -> Void = { _ in }
    var onInvalid: (UsageAccountObservation) -> Void = { _ in }
    var onDisconnected: (String) -> Void = { _ in }
    var connectSelectedPage: () -> Void = {}
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var generation = UUID()
    private var setupRequested = false
    private var installationCarrier: String?
    private var bindingRevision = UUID()

    func start() {
        guard !CompanionPreferences.simulated, process == nil,
              let resources = Bundle.main.resourceURL?.appendingPathComponent("Bridge") else { return }
        let service = resources.appendingPathComponent("web/service.py")
        guard FileManager.default.fileExists(atPath: service.path) else { status = "网页接口尚未随程序安装"; return }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("local.achu.companion/web-usage")
        let child = Process(), inbound = Pipe(), outbound = Pipe()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        child.arguments = ["python3", service.path, "--state-dir", directory.path, "--resources", resources.path]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin"
        child.environment = environment
        child.standardInput = inbound; child.standardOutput = outbound; child.standardError = FileHandle.nullDevice
        let token = UUID(); generation = token
        let reader = ManagedWebLines()
        outbound.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            for line in reader.append(data) {
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    self.receive(line)
                }
            }
        }
        child.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.available = false; self.connecting = false; self.binding = ""; self.process = nil
                self.status = "网页接口暂不可用；可在伴侣中重新连接"
                if self.hasSelectedTarget { self.onDisconnected(self.status) }
            }
        }
        do {
            try child.run(); process = child; input = inbound; output = outbound
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self, self.generation == token, !self.available else { return }
                self.stop(); self.status = "网页接口加载失败，请在伴侣中重试连接"
            }
        } catch { status = "本机网页接口无法启动，聊天功能仍可使用" }
    }
    func prepareAuthorization() {
        start()
        guard available else { status = "网页接口正在加载，请稍后重试"; return }
        // Installation is a normal manager consent flow. Never edit browser
        // preferences, load unpacked extensions, or ask for an extension ID.
        let carriers = ["com.google.Chrome", "com.microsoft.edgemac"].filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier:$0) != nil && Self.hasRuntime(browser:$0)
        }
        guard let browser = Self.installationBrowser(bound:sourceBrowser, available:carriers) else {
            status = sourceBrowser == nil && carriers.count > 1
                ? "检测到多个可用浏览器，请先在要连接的 Claude 网页输入区按 ⌃⌥E"
                : "当前浏览器没有可运行的网页组件；聊天功能仍可使用。"
            return
        }
        // This selects only the installation carrier, never an input or account.
        installationCarrier = browser
        setupRequested = true
        status = "已准备网页接口，请确认即将打开的安装授权"
        command(["kind":"setup","browser":browser])
    }
    func bind(url: String, browser: String?) {
        bindingRevision = UUID()
        hasSelectedTarget = true; sourceBrowser = browser
        guard available else { status = "网页接口正在加载，可稍后在伴侣中连接"; return }
        guard authorized || setupRequested else {
            prepareAuthorization(); return
        }
        connecting = true; binding = ""; status = "正在连接你指定的 Claude 网页"
        command(["kind":"bind","url":url,"browser":browser ?? "","requestID":bindingRevision.uuidString])
    }
    func waitForBinding() async {
        let revision = bindingRevision
        let deadline = ContinuousClock.now.advanced(by:.milliseconds(1400))
        while connecting && revision == bindingRevision && ContinuousClock.now < deadline {
            try? await Task.sleep(for:.milliseconds(20))
        }
        if connecting && revision == bindingRevision {
            command(["kind":"unbind"]); connecting = false
            status = "未收到当前网页确认；聊天功能继续，可在伴侣中重新连接"
        }
    }
    func read() throws {
        guard available, !binding.isEmpty else { throw BridgeError.message(status) }
        command(["kind":"read"])
    }
    func unbind() {
        bindingRevision = UUID()
        hasSelectedTarget = false; sourceBrowser = nil; connecting = false; binding = ""
        command(["kind":"unbind"])
    }
    func revoke() {
        bindingRevision = UUID()
        command(["kind":"revoke"]); authorized = false; setupRequested = false
        binding = ""; connecting = false; status = "网页授权已撤销"
    }
    func stop() {
        bindingRevision = UUID()
        generation = UUID(); output?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close()
        if process?.isRunning == true { process?.terminate() }
        process = nil; input = nil; output = nil; available = false; connecting = false; binding = ""
    }
    private func command(_ body: [String:Any]) {
        guard let input, let data = try? JSONSerialization.data(withJSONObject:body) else { return }
        do { try input.fileHandleForWriting.write(contentsOf:data + Data([10])) }
        catch { status = "网页接口连接中断" }
    }
    private func receive(_ data: Data) {
        guard let body = try? JSONSerialization.jsonObject(with:data) as? [String:Any], let kind = body["kind"] as? String else { return }
        switch kind {
        case "ready":
            available = true; authorized = body["authorized"] as? Bool == true
            status = authorized ? "网页接口已准备，连接当前网页后获取额度" : "网页接口已准备，首次连接需确认安装授权"
        case "install":
            guard let raw = body["url"] as? String, let url = URL(string:raw), url.scheme == "http", url.host == "127.0.0.1", url.path.hasPrefix("/install/"),
                  let browser = installationCarrier, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier:browser) else { return }
            NSWorkspace.shared.open([url], withApplicationAt:app, configuration:NSWorkspace.OpenConfiguration())
        case "bound":
            guard hasSelectedTarget, body["requestID"] as? String == bindingRevision.uuidString,
                  let selected = body["binding"] as? String, selected.hasPrefix("web-") else { return }
            authorized = true; connecting = false; binding = selected
            status = "网页已连接，正在读取当前账户额度"; onBound(selected)
        case "usage":
            guard hasSelectedTarget, body["binding"] as? String == binding, let evidence = try? Self.evidence(body) else { return }
            status = "已获取当前网页账户额度"; onEvidence(evidence)
        case "invalid":
            guard hasSelectedTarget, body["binding"] as? String == binding,
                  let epoch = body["epoch"] as? String, let sequence = Self.sequence(body["sequence"]) else { return }
            status = "当前网页账户或额度暂不可用，旧额度已隐藏"
            onInvalid(.init(source:.usagePage,binding:binding,epoch:epoch,sequence:sequence,identity:nil))
        case "disconnected":
            if let request = body["requestID"] as? String, request != bindingRevision.uuidString { return }
            connecting = false; binding = ""
            status = body["reason"] as? String == "heartbeat-timeout" ? "网页连接已断开，旧额度已隐藏" : "未确认指定网页，请在伴侣中连接已指定网页"
            if hasSelectedTarget { onDisconnected(status) }
        default: break
        }
    }
    nonisolated private static func sequence(_ raw: Any?) -> Int? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.rounded() == number.doubleValue, (0...1_000_000_000).contains(number.doubleValue) else { return nil }
        return number.intValue
    }
    nonisolated static func installationBrowser(bound: String?, available: [String]) -> String? {
        if let bound { return available.contains(bound) ? bound : nil }
        let carriers = Set(available)
        return carriers.count == 1 ? carriers.first : nil
    }
    nonisolated static func evidence(_ body: [String:Any]) throws -> UsageEvidence {
        guard Set(body.keys) == ["kind","binding","url","epoch","sequence","account","usage"],
              let binding = body["binding"] as? String, binding.range(of:"^web-[A-Za-z0-9_-]{1,96}$",options:.regularExpression) != nil,
              let url = body["url"] as? String, let parts = URLComponents(string:url), parts.scheme == "https", parts.host == "claude.ai", parts.port == nil, parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              let epoch = body["epoch"] as? String, !epoch.isEmpty, epoch.count <= 128, let sequence = sequence(body["sequence"]),
              let account = body["account"] as? [String:String], Set(account.keys) == ["fingerprint","displayName"],
              let fingerprint = account["fingerprint"], let label = account["displayName"],
              label.range(of:#"^[^\s@]\*{3}@[^\s@]+$"#,options:.regularExpression) != nil,
              let usage = body["usage"] as? [String:Any] else { throw ClaudeUsageError.malformed }
        let identity = UsageAccountIdentity(fingerprint:fingerprint,displayName:label)
        guard identity.valid else { throw ClaudeUsageError.malformed }
        var result = try UsageEvidence.statusLine(JSONSerialization.data(withJSONObject:usage),binding:binding)
        result = .init(source:.usagePage,binding:binding,snapshot:result.snapshot,identity:identity,epoch:epoch,sequence:sequence,pageURL:url)
        return result
    }
    private static func hasRuntime(browser: String) -> Bool {
        let folder: String
        switch browser { case "com.google.Chrome": folder = "Google/Chrome"; case "com.microsoft.edgemac": folder = "Microsoft Edge"; default: return false }
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/" + folder)
        let profiles = (try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)) ?? []
        for profile in profiles.prefix(64) where profile.lastPathComponent == "Default" || profile.lastPathComponent.hasPrefix("Profile ") {
            let extensionPath = profile.appendingPathComponent("Extensions/dhdgffkkebhmkfjojejmpbldmpobfkfo")
            if FileManager.default.fileExists(atPath:extensionPath.path) { return true }
        }
        return false
    }
}

private final class ManagedWebLines: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    func append(_ data: Data) -> [Data] {
        lock.withLock {
            buffer.append(data)
            guard buffer.count <= 131072 else { buffer.removeAll(); return [] }
            var result: [Data] = []
            while let end = buffer.firstIndex(of:10) {
                let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
                if line.count <= 65536 { result.append(line) }
            }
            return result
        }
    }
}
