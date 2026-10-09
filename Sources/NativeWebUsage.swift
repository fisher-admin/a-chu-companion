import AppKit
import ApplicationServices
import SwiftUI

@MainActor struct WebUsageSelection {
    let app: NSRunningApplication
    let window: AXUIElement
    let input: AXUIElement?
    var allowed: @MainActor () -> Bool = { true }
}

/// This reader never owns, changes or invokes the message delivery lease.
@MainActor final class NativeWebUsage: ObservableObject {
    struct PageState { let url: String; let wasUsage: Bool }
    struct Environment {
        var discover: @MainActor () throws -> [WebUsageSelection] = WebUsageAccessibility.discover
        var discoveryDetails: @MainActor () -> String = { WebUsageAccessibility.discoverySummary }
        var available: @MainActor (WebUsageSelection) -> Bool = WebUsageAccessibility.available
        var foreground: @MainActor (WebUsageSelection) -> Bool = WebUsageAccessibility.foreground
        var activate: @MainActor (WebUsageSelection) -> Void = WebUsageAccessibility.activate
        var begin: @MainActor (WebUsageSelection) throws -> PageState = WebUsageAccessibility.begin
        var account: @MainActor (WebUsageSelection) async throws -> UsageAccountIdentity = WebUsageAccessibility.account
        var quota: @MainActor (WebUsageSelection) async throws -> ClaudeUsageSnapshot = WebUsageAccessibility.quota
        var restore: @MainActor (WebUsageSelection,PageState) async throws -> Void = WebUsageAccessibility.restore
    }
    @Published private(set) var status = "直接读取所选网页的 Usage，无需安装浏览器组件"
    @Published private(set) var busy = false { didSet { onBusyChanged(busy) } }
    @Published private(set) var hasSelectedTarget = false
    @Published private(set) var binding = ""
    var onBound: (String) -> Void = { _ in }
    var onBusyChanged: (Bool) -> Void = { _ in }
    var onReading: (String) -> Void = { _ in }
    var onEvidence: (UsageEvidence) -> Void = { _ in }
    var onInvalid: (UsageAccountObservation) -> Void = { _ in }
    var canRead: () -> Bool = { true }
    private let environment: Environment
    private var selection: WebUsageSelection?
    private var revision = UUID()
    private var epoch = UUID().uuidString
    private var sequence = 0
    private var lastFingerprint: String?
    private var restorationFailed = false

    init(environment: Environment = .init()) { self.environment = environment }
    func bind(_ selected: WebUsageSelection) {
        unbind(); selection = selected; hasSelectedTarget = true
        binding = "web-native-" + revision.uuidString
        status = "网页窗口已指定，正在准备直接读取额度"; onBound(binding)
    }
    func unbind() {
        revision = UUID(); epoch = UUID().uuidString; selection = nil
        hasSelectedTarget = false; binding = ""; busy = false; sequence = 0; lastFingerprint = nil; restorationFailed = false
    }
    func readOpenUsage() async throws {
        if selection == nil {
            let windows = try environment.discover()
            guard windows.count == 1, let window = windows.first else {
                status = windows.isEmpty ? "请先在浏览器当前标签显示 Claude「设置 → Usage」，然后点击读取。" : "已打开多个 Usage 窗口，请先在所需 Claude 输入区按 ⌃⌥E 指定窗口。"
                if windows.isEmpty { status += " " + environment.discoveryDetails() }
                throw BridgeError.message(status)
            }
            bind(window)
        }
        try await read(explicit:true)
    }
    func read(explicit: Bool) async throws {
        guard !busy else { throw BridgeError.message("网页额度正在读取，请稍候。") }
        guard canRead() else { throw BridgeError.message("发送任务尚未完成，额度读取稍后重试。") }
        guard let pinned = selection else { throw BridgeError.message("请先指定 Claude 网页窗口。") }
        let token = revision
        var selected = pinned
        selected.allowed = { [weak self] in self?.revision == token && self?.canRead() == true }
        guard environment.available(selected) else { invalidate("此前网页窗口已关闭，请重新连接。"); throw BridgeError.message(status) }
        if !explicit && (restorationFailed || !environment.foreground(selected)) {
            status = "网页不在前台，本次未自动刷新；可在伴侣主动读取。"
            throw BridgeError.message(status)
        }
        if explicit && !environment.foreground(selected) {
            environment.activate(selected)
            for _ in 0..<20 where !environment.foreground(selected) {
                try Task.checkCancellation()
                guard selected.allowed() else { throw CancellationError() }
                try await Task.sleep(for:.milliseconds(50))
            }
        }
        func current() throws {
            try Task.checkCancellation()
            guard token == revision, canRead(), environment.available(selected), environment.foreground(selected) else { throw CancellationError() }
        }
        try current(); busy = true; status = "正在核对网页账户并读取 Usage…"
        if explicit { onBound(binding) }
        onReading(binding)
        var original: PageState?
        var stage = "定位原页面"
        do {
            original = try environment.begin(selected)
            stage = "核对读取前账户"; status = "正在核对网页当前账户…"
            let before = try await environment.account(selected); try current()
            stage = "读取 Usage"; status = "正在读取网页 Usage…"
            let candidate = try await environment.quota(selected); try current()
            stage = "核对读取后账户"; status = "正在复核网页当前账户…"
            let after = try await environment.account(selected); try current()
            guard before.valid, before.fingerprint == after.fingerprint else { throw BridgeError.message("读取期间网页账户已变化，旧额度已隐藏。") }
            stage = "恢复原页面"; status = "正在恢复网页原界面…"
            try await environment.restore(selected,original!); original = nil; try current()
            if lastFingerprint != before.fingerprint { epoch = UUID().uuidString }
            lastFingerprint = before.fingerprint; sequence += 1
            restorationFailed = false; busy = false; status = "已读取网页额度 · 已核对当前账户"
            onEvidence(.init(source:.usagePage,binding:binding,snapshot:candidate,identity:before,epoch:epoch,sequence:sequence))
        } catch {
            guard token == revision else { throw CancellationError() }
            if let original, environment.available(selected), environment.foreground(selected) {
                do { try await environment.restore(selected,original) }
                catch { restorationFailed = true }
            } else if original != nil { restorationFailed = true }
            busy = false
            invalidate(restorationFailed ? "网页未能恢复原界面，请关闭网页设置后主动重试；自动读取已暂停。" : (error is CancellationError ? "网页读取已取消，未抢占其他程序的焦点。" : "\(stage)：\(error.localizedDescription)"))
            throw BridgeError.message(status)
        }
    }
    private func invalidate(_ message: String) {
        sequence += 1; lastFingerprint = nil; epoch = UUID().uuidString; status = message
        if !binding.isEmpty { onInvalid(.init(source:.usagePage,binding:binding,epoch:epoch,sequence:sequence,identity:nil)) }
    }
}
