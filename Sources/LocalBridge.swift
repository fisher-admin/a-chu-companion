import Foundation
import Darwin
import SwiftUI

final class LocalBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptor: Int32 = -1
    private var worker: Task<Void, Never>?
    private var directory: URL?
    private var publishedFile: URL?
    private(set) var token = ""
    private(set) var connectionFile: URL?
    private var usageRequest: (id: String, binding: String?, url: String?)?
    func requestWebUsage(binding: String? = nil, url: String? = nil) {
        lock.withLock { usageRequest = (UUID().uuidString, binding, url) }
    }
    func start(directory requested: URL? = nil, publication: URL? = nil, receive: @escaping @Sendable (Data) async -> Bool) throws {
        stop()
        let directory = (requested ?? URL(fileURLWithPath: "/tmp")).appendingPathComponent("achu-" + String(getuid()) + "-" + String(UUID().uuidString.prefix(8)))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        self.directory = directory
        var started = false
        defer { if !started { stop() } }
        let path = directory.appendingPathComponent("events.sock").path
        guard path.utf8.count < 104 else { throw BridgeError.message("桥接路径过长。") }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BridgeError.message("无法建立本机桥接。") }
        lock.withLock { descriptor = fd }
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { target in
            target.initializeMemory(as: UInt8.self, repeating: 0)
            target.copyBytes(from: Array(path.utf8))
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0, listen(fd, 4) == 0 else { throw BridgeError.message("桥接端口不可用。") }
        chmod(path, 0o600)
        token = UUID().uuidString + UUID().uuidString
        let file = directory.appendingPathComponent("connection.json")
        let data = try JSONSerialization.data(withJSONObject: ["version":1,"token":token,"socket":path])
        try data.write(to: file, options: .atomic)
        chmod(file.path, 0o600)
        if let publication {
            let parent = publication.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard !FileManager.default.fileExists(atPath: publication.path) || (try? publication.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw BridgeError.message("连接路径不能是符号链接。") }
            try data.write(to: publication, options: .atomic); chmod(publication.path, 0o600)
            publishedFile = publication
        }
        self.directory = directory; connectionFile = publication ?? file
        lock.withLock { descriptor = fd }
        started = true
        worker = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                guard let self, self.lock.withLock({ self.descriptor == fd }) else { return }
                let client = accept(fd, nil, nil)
                guard client >= 0 else { return }
                var timeout = timeval(tv_sec: 0, tv_usec: 250_000)
                setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                var noSignal: Int32 = 1
                setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
                let packet = Self.frame(client)
                let accepted = if let packet { await receive(packet) } else { false }
                var acknowledgement: [String: Any] = ["ok": accepted]
                if accepted, let packet, let object = try? JSONSerialization.jsonObject(with: packet) as? [String: Any],
                   let binding = object["binding"] as? String, binding.hasPrefix("web-"),
                   let request = self.lock.withLock({ self.usageRequest }),
                   (request.binding == nil || request.binding == binding),
                   (request.url == nil || request.url == object["url"] as? String) {
                    acknowledgement["requestUsage"] = request.id
                }
                let reply = (try? JSONSerialization.data(withJSONObject: acknowledgement)) ?? Data(#"{"ok":false}"#.utf8)
                var length = UInt32(reply.count).bigEndian
                withUnsafeBytes(of: &length) { _ = Darwin.write(client, $0.baseAddress, $0.count) }
                reply.withUnsafeBytes { _ = Darwin.write(client, $0.baseAddress, $0.count) }
                Darwin.close(client)
            }
        }
    }
    private static func read(_ fd: Int32, count: Int) -> Data? {
        var data = Data(count: count); var offset = 0
        while offset < count {
            let amount = data.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!.advanced(by: offset), count - offset) }
            guard amount > 0 else { return nil }; offset += amount
        }
        return data
    }
    private static func frame(_ fd: Int32) -> Data? {
        guard let header = read(fd, count: 4) else { return nil }
        let size = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard size > 0, size <= 8 * 1024 * 1024 else { return nil }
        return read(fd, count: Int(size))
    }
    func stop() {
        lock.withLock { usageRequest = nil }
        let fd = lock.withLock { let value = descriptor; descriptor = -1; return value }
        if fd >= 0 { shutdown(fd, SHUT_RDWR); Darwin.close(fd) }
        worker?.cancel(); worker = nil
        if let file = publishedFile, let data = try? Data(contentsOf: file),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object["token"] as? String == token {
            try? FileManager.default.removeItem(at: file)
        }
        publishedFile = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil; connectionFile = nil
    }
    deinit { stop() }
}

struct BridgeChoice: Identifiable {
    let id: String
    var delivery: CLIDeliveryOrigin? = nil
    var source: BridgeSourceDetails? = nil
    var reportedAt: Date? = nil
    var hasReplies = false
    var name: String {
        let label = id.hasPrefix("web-") ? "Claude 网页 · " : "Claude CLI · "
        return label + String(id.suffix(6)) + (source?.workspace.map { " · " + $0 } ?? "")
    }
    var reportDescription: String {
        guard let reportedAt else { return "报告时间未知" }
        let minutes = max(0, Int(Date().timeIntervalSince(reportedAt) / 60))
        if minutes == 0 { return "刚收到报告" }
        return "\(minutes)分钟前收到报告"
    }
}
@MainActor final class BridgeCoordinator: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var choices: [BridgeChoice] = []
    @Published private(set) var selected = ""
    @Published private(set) var status = "CLI / Chrome 只读桥接，待真实验收"
    @Published private(set) var connectionPath = ""
    var onStop: () -> Void = {}
    var onTick: () -> Void = {}
    var onSelection: () -> Void = {}
    var onCLIReport: () -> Void = {}
    var onSnapshot: (ReplySnapshot) -> Void = { _ in }
    var onUsageAccount: (UsageAccountObservation) -> Void = { _ in }
    var onUsage: (UsageEvidence) -> Void = { _ in }
    var onUsageConnection: (String?) -> Void = { _ in }
    private let server = LocalBridge()
    private var decoder = BridgeDecoder()
    private var snapshots: [String: ReplySnapshot] = [:]
    private var visible: [String: Set<ReplyAddress>] = [:]
    private var received: [String: Date] = [:]
    private var clock: Task<Void, Never>?
    var cliChoices: [BridgeChoice] {
        choices.filter { $0.id.hasPrefix("cli-") }.sorted {
            if $0.reportedAt != $1.reportedAt { return ($0.reportedAt ?? .distantPast) > ($1.reportedAt ?? .distantPast) }
            return $0.id < $1.id
        }
    }
    var selectedName: String { choices.first { $0.id == selected }?.name ?? BridgeChoice(id: selected).name }
    var visibleHistory: [ReplyWork] {
        guard let snapshot = snapshots[selected] else { return [] }
        return snapshot.messages.filter { $0.author == .assistant && $0.completed == true && visible[selected, default: []].contains($0.address) }.map { .init(candidate: .init(ordinal: $0.ordinal, text: $0.text, segment: $0.segment), conversation: snapshot.conversation, manual: true) }
    }
    func start() {
        do {
            let publication = CompanionPreferences.simulated ? nil : FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("local.achu.companion/bridge/connection.json")
            try server.start(publication: publication) { [weak self] data in
                await self?.receive(data) ?? false
            }
            connectionPath = server.connectionFile?.path ?? ""; enabled = true
            status = "桥接已开启，等待当前聊天入口连接"
        } catch { status = error.localizedDescription }
    }
    private func receive(_ data: Data) -> Bool {
        do {
            let update = try decoder.accept(data, token: server.token)
            if update.needsSync { status = "缺少消息批次，等待新消息或完整快照；不猜测缺失内容。"; return false }
            if update.waitingForBatch { status = "收到先到的后续批次，正在等待前序正文；不显示缺段内容。"; return true }
            if update.duplicate { return true }
            if !choices.contains(where: { $0.id == update.binding }) { choices.append(.init(id: update.binding)) }
            let now = Date()
            received[update.binding] = now
            if let index = choices.firstIndex(where: { $0.id == update.binding }) {
                // Every statusLine report is an origin observation. A missing
                // origin revokes input capability without losing the reader.
                if update.accountObservation != nil || update.evidence != nil {
                    choices[index].delivery = update.delivery
                }
                choices[index].reportedAt = now
                if let source = update.source {
                    let previous = choices[index].source
                    choices[index].source = .init(workspace: source.workspace ?? previous?.workspace, model: source.model ?? previous?.model)
                }
                if let snapshot = update.snapshot {
                    choices[index].hasReplies = snapshot.messages.contains { $0.author == .assistant && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                }
            }
            if let observation = update.accountObservation { onUsageAccount(observation) }
            if let evidence = update.evidence { onUsage(evidence) }
            if update.binding.hasPrefix("cli-") { onCLIReport() }
            if let snapshot = update.snapshot {
                snapshots[update.binding] = snapshot; visible[update.binding] = update.visible; received[update.binding] = Date()
                if selected == update.binding {
                    status = "已绑定回复来源；输入位置由连接快捷键单独核对"
                    onSnapshot(snapshot)
                }
            }
            return true
        } catch { status = "桥接数据未通过校验，未采用。"; return false }
    }
    func select(_ binding: String) {
        guard choices.contains(where: { $0.id == binding }) else { return }
        selected = binding; clock?.cancel(); onSelection()
        onUsageConnection(binding)
        status = "已绑定回复来源；输入位置由连接快捷键单独核对"
        if let snapshot = snapshots[binding] { onSnapshot(snapshot) }
        clock = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let time = received[selected], Date().timeIntervalSince(time) < 15 { onTick() }
                else { status = "来源暂时没有新报告；已译内容保留，等待重连或下一条消息。" }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
    func clearSelection() {
        clock?.cancel(); clock = nil; selected = ""
        onSelection(); onUsageConnection(nil)
        status = "只读入口与候选会话已保留，请选择当前使用的来源。"
    }
    func stop() {
        onUsageConnection(nil)
        onStop(); clock?.cancel(); clock = nil; selected = ""; enabled = false; choices = []; snapshots = [:]; visible = [:]; received = [:]
        decoder = BridgeDecoder(); server.stop(); connectionPath = ""; status = "桥接已停止"
    }
    func requestUsage(binding: String? = nil, url: String? = nil) throws {
        if !enabled { start() }
        guard enabled else { throw BridgeError.message(status) }
        server.requestWebUsage(binding: binding, url: url)
    }
}
