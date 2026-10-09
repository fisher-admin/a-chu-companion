import Foundation
import CoreFoundation

struct BridgeSourceDetails: Equatable {
    let workspace: String?
    let model: String?
}

struct BridgeUpdate {
    let binding: String
    var source: BridgeSourceDetails? = nil
    var delivery: CLIDeliveryOrigin? = nil
    var snapshot: ReplySnapshot? = nil
    var evidence: UsageEvidence? = nil
    var accountObservation: UsageAccountObservation? = nil
    var visible: Set<ReplyAddress> = []
    var duplicate = false
    var needsSync = false
    var waitingForBatch = false
}

struct BridgeDecoder {
    private struct Batch: Equatable {
        let text: String
        let final: Bool
    }
    private struct Stream {
        var epoch: String
        var sequence = -1
        var messages: [ChatMessage] = []
        var indices: [String: Int] = [:]
        var nextOrdinal = 2
        var closed: Set<String> = []
        var ordinals: [String: Int] = [:]
        var pending: [String: [Int: Batch]] = [:]
    }
    private struct UsageStream { let epoch: String; let sequence: Int }
    private var usageStreams: [String: UsageStream] = [:]
    private var retiredUsageEpochs: [String: Set<String>] = [:]
    private var streams: [String: Stream] = [:]
    private var retiredEpochs: [String: Set<String>] = [:]
    private func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
              number.doubleValue >= 0, number.doubleValue <= 1_000_000_000 else { return nil }
        return number.intValue
    }
    private func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
    private mutating func commit(_ stream: Stream, binding: String) throws {
        if let old = streams[binding], old.epoch != stream.epoch {
            guard (retiredEpochs[binding]?.count ?? 0) < 64 else { throw BridgeError.message("来源重启过多，请重新启用桥接。") }
            retiredEpochs[binding, default: []].insert(old.epoch)
        }
        streams[binding] = stream
    }
    mutating func accept(_ data: Data, token: String) throws -> BridgeUpdate {
        let allowed: Set<String> = ["version","token","kind","binding","epoch","sequence","messageID","turnID","text","final","url","messages","usage","account","source","delivery"]
        guard data.count <= 8 * 1024 * 1024,
              let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(body.keys).isSubset(of: allowed), integer(body["version"]) == 1,
              body["token"] as? String == token,
              let kind = body["kind"] as? String, ["snapshot","delta","usage"].contains(kind),
              let binding = body["binding"] as? String, binding.count <= 100,
              binding.range(of: "^(web|cli)-[A-Za-z0-9_-]+$", options: .regularExpression) != nil,
              let epoch = body["epoch"] as? String, !epoch.isEmpty, epoch.count <= 128,
              let sequence = integer(body["sequence"]), sequence >= 0 else { throw BridgeError.message("桥接报文或权限无效，未采用。") }
        var source: BridgeSourceDetails?
        var delivery: CLIDeliveryOrigin?
        if let raw = body["delivery"] {
            guard kind == "usage", binding.hasPrefix("cli-"), let value = raw as? [String: Any],
                  Set(value.keys) == ["pid","tty","started","tag"], let pid = integer(value["pid"]),
                  let tty = value["tty"] as? String, let started = value["started"] as? String,
                  let tag = value["tag"] as? String else { throw BridgeError.message("CLI 输入来源无效。") }
            let origin = CLIDeliveryOrigin(pid: Int32(pid), tty: tty, started: started, tag: tag)
            guard origin.valid(for: binding) else { throw BridgeError.message("CLI 输入来源不匹配。") }
            delivery = origin
        }
        if let raw = body["source"] {
            guard binding.hasPrefix("cli-"), let value = raw as? [String: Any], Set(value.keys).isSubset(of: ["workspace","model"]) else {
                throw BridgeError.message("CLI 来源摘要无效。")
            }
            let controls = CharacterSet.controlCharacters.union(.init(charactersIn: "\u{2028}\u{2029}"))
            for (key, rawLabel) in value {
                guard let label = rawLabel as? String, !label.isEmpty, label.count <= 80,
                      !label.unicodeScalars.contains(where: controls.contains),
                      key != "workspace" || (!label.contains("/") && !label.contains("\\")) else { throw BridgeError.message("CLI 来源摘要无效。") }
            }
            source = .init(workspace: value["workspace"] as? String, model: value["model"] as? String)
        }
        if streams[binding] == nil && streams.count >= 8 { throw BridgeError.message("桥接来源过多，请停止旧连接后再连接。") }
        if binding.hasPrefix("web-") {
            guard let rawURL = body["url"] as? String, let url = URLComponents(string: rawURL),
                  url.scheme == "https", url.host == "claude.ai", url.user == nil, url.password == nil,
                  url.port == nil, url.query == nil, url.fragment == nil else { throw BridgeError.message("网页来源不符合连接范围。") }
        }
        if retiredEpochs[binding]?.contains(epoch) == true { return .init(binding: binding, duplicate: true) }
        if kind == "usage" {
            guard let usage = body["usage"] as? [String: Any] else { throw ClaudeUsageError.malformed }
            let identity: UsageAccountIdentity?
            if let account = body["account"] {
                guard let value = account as? [String: Any], Set(value.keys) == ["fingerprint", "displayName"],
                      let fingerprint = value["fingerprint"] as? String, let label = value["displayName"] as? String else { throw ClaudeUsageError.malformed }
                let decoded = UsageAccountIdentity(fingerprint: fingerprint, displayName: label)
                guard decoded.valid else { throw ClaudeUsageError.malformed }; identity = decoded
            } else { identity = nil }
            let payload = try JSONSerialization.data(withJSONObject: usage)
            let parsed: UsageEvidence?
            do { parsed = try UsageEvidence.statusLine(payload, binding: binding) }
            catch ClaudeUsageError.unavailable { parsed = nil }
            if retiredUsageEpochs[binding]?.contains(epoch) == true { return .init(binding: binding, duplicate: true) }
            if let old = usageStreams[binding] {
                if old.epoch == epoch && sequence <= old.sequence { return .init(binding: binding, duplicate: true) }
                if old.epoch != epoch {
                    guard (retiredUsageEpochs[binding]?.count ?? 0) < 64 else { throw ClaudeUsageError.malformed }
                    retiredUsageEpochs[binding, default: []].insert(old.epoch)
                }
            } else if usageStreams.count >= 8 { throw ClaudeUsageError.malformed }
            usageStreams[binding] = .init(epoch: epoch, sequence: sequence)
            let evidenceSource: UsageEvidenceSource = binding.hasPrefix("web-") ? .usagePage : .statusLine
            let observation = UsageAccountObservation(source: evidenceSource, binding: binding, epoch: epoch, sequence: sequence, identity: identity)
            let evidence = parsed.map { UsageEvidence(source: evidenceSource, binding: binding, snapshot: $0.snapshot, identity: identity, epoch: epoch, sequence: sequence, pageURL: body["url"] as? String) }
            return .init(binding: binding, source: source, delivery: delivery, evidence: evidence, accountObservation: evidence == nil ? observation : nil)
        }
        let conversation = "bridge:" + binding + ":" + epoch
        var stream = streams[binding].flatMap { $0.epoch == epoch ? $0 : nil } ?? Stream(epoch: epoch)
        if kind == "snapshot" {
            guard binding.hasPrefix("web-"), let raw = body["messages"] as? [[String: Any]], raw.count <= 32,
                  let complete = boolean(body["final"]) else { throw BridgeError.message("网页快照不完整。") }
            if sequence <= stream.sequence { return .init(binding: binding, duplicate: true) }
            var messages: [ChatMessage] = []; var visible: Set<ReplyAddress> = []
            for value in raw {
                guard Set(value.keys).isSubset(of: ["ordinal","segment","author","text","completed","visible"]),
                      let ordinal = integer(value["ordinal"]), ordinal > 0,
                      let author = value["author"] as? String, ["assistant","user"].contains(author),
                      let text = value["text"] as? String, text.count <= 100_000,
                      let completed = boolean(value["completed"]) else { throw BridgeError.message("网页正文结构无效。") }
                let segment = value["segment"] == nil ? 0 : (integer(value["segment"]) ?? -1)
                guard segment >= 0 else { throw BridgeError.message("分段序号无效。") }
                if let flag = value["visible"], boolean(flag) == nil { throw BridgeError.message("可见状态无效。") }
                if boolean(value["visible"]) == true { visible.insert(.init(ordinal: ordinal, segment: segment)) }
                messages.append(.init(ordinal: ordinal, author: author == "assistant" ? .assistant : .user, text: text, segment: segment, completed: completed))
            }
            let addresses = messages.map(\.address)
            guard addresses == addresses.sorted(), Set(addresses).count == addresses.count else { throw BridgeError.message("网页消息顺序不完整。") }
            stream.sequence = sequence; stream.messages = messages; try commit(stream, binding: binding)
            return .init(binding: binding, snapshot: .init(conversation: conversation, messages: messages, foundTranscript: true, responseComplete: complete), visible: visible)
        }
        guard binding.hasPrefix("cli-"), let messageID = body["messageID"] as? String, !messageID.isEmpty, messageID.count <= 128,
              let text = body["text"] as? String, text.count <= 100_000,
              let final = boolean(body["final"]) else { throw BridgeError.message("CLI 分段报文无效。") }
        let last = stream.indices[messageID] ?? -1
        if sequence <= last { return .init(binding: binding, duplicate: true) }
        guard !stream.closed.contains(messageID), stream.indices.count < 1024 || stream.indices[messageID] != nil else { return .init(binding: binding, needsSync: true) }
        let incoming = Batch(text: text, final: final)
        if let queued = stream.pending[messageID]?[sequence] {
            return queued == incoming ? .init(binding: binding, duplicate: true) : .init(binding: binding, needsSync: true)
        }
        if sequence != last + 1 {
            // MessageDisplay command hooks can run concurrently. Keep a small
            // bounded window; never publish a tail before its missing prefix.
            let waiting = stream.pending.values.flatMap { $0.values }
            guard sequence <= last + 8, waiting.count < 32,
                  waiting.reduce(0, { $0 + $1.text.utf8.count }) + text.utf8.count <= 2 * 1024 * 1024 else {
                return .init(binding: binding, needsSync: true)
            }
            stream.pending[messageID, default: [:]][sequence] = incoming
            try commit(stream, binding: binding)
            return .init(binding: binding, waitingForBatch: true)
        }
        let ordinal = stream.ordinals[messageID] ?? stream.nextOrdinal
        if stream.ordinals[messageID] == nil { stream.nextOrdinal += 2 }
        stream.ordinals[messageID] = ordinal
        var batches = stream.pending.removeValue(forKey: messageID) ?? [:]
        batches[sequence] = incoming
        var full = stream.messages.first(where: { $0.ordinal == ordinal })?.text ?? ""
        var next = sequence
        var completed = false
        while let batch = batches.removeValue(forKey: next) {
            full += batch.text
            guard full.count <= 100_000 else { throw BridgeError.message("CLI 原文过长，未采用不完整内容。") }
            stream.indices[messageID] = next
            completed = batch.final
            if completed { break }
            next += 1
        }
        if !completed && !batches.isEmpty { stream.pending[messageID] = batches }
        let message = ChatMessage(ordinal: ordinal, author: .assistant, text: full, completed: completed)
        if let index = stream.messages.firstIndex(where: { $0.ordinal == ordinal }) { stream.messages[index] = message }
        else { stream.messages.append(message) }
        if completed { stream.closed.insert(messageID) }
        stream.messages = Array(stream.messages.suffix(16))
        try commit(stream, binding: binding)
        // MessageDisplay final terminates one message, not the whole turn.
        return .init(binding: binding, source: source, snapshot: .init(conversation: conversation, messages: stream.messages, foundTranscript: true, responseComplete: false))
    }
}
