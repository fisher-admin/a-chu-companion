import Foundation
import AppKit

@main struct OptimizationLifecycleTests {
    @MainActor static func settle(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() { precondition(ContinuousClock.now < deadline); try await Task.sleep(for: .milliseconds(5)) }
    }
    @MainActor static func main() async throws {
        let name = "achu-test-" + UUID().uuidString; let prefs = UserDefaults(suiteName: name)!
        defer { prefs.removePersistentDomain(forName: name) }
        prefs.set("https://original.example/v1", forKey:"baseURL"); Credentials.bindLegacyConfiguration(settings:prefs)
        let original = try TranslationProfile.scope(provider:.openAI,baseURL:"https://original.example/v1")
        let other = try TranslationProfile.scope(provider:.openAI,baseURL:"https://other.example/v1")
        let vault = [RemoteTranslationProvider.openAI.credentialAccount:"synthetic-only-key"]; var legacyReads = 0
        let read: (String) throws -> String = { if $0 == RemoteTranslationProvider.openAI.credentialAccount { legacyReads += 1 }; return vault[$0] ?? "" }
        let absent = try Credentials.readBoundCredential(provider:.openAI,scope:other,settings:prefs,read:read)
        precondition(absent.isEmpty && legacyReads == 0)
        let fallback = try Credentials.readBoundCredential(provider:.openAI,scope:original,settings:prefs,read:read)
        precondition(fallback == "synthetic-only-key" && vault[original] == nil && vault[RemoteTranslationProvider.openAI.credentialAccount] != nil)
        let reads = legacyReads
        _ = try Credentials.readBoundCredential(provider:.openAI,scope:original,settings:prefs,read:read)
        precondition(legacyReads == reads + 1 && vault.count == 1)
        try TranslationProfileMetadata.save(baseURL:"https://original.example/v1",model:"chosen-model",settings:prefs)
        precondition(TranslationProfileMetadata.model(baseURL:"https://original.example/v1",settings:prefs) == "chosen-model" && TranslationProfileMetadata.model(baseURL:"https://other.example/v1",settings:prefs).isEmpty)
        print("PASS: credential fallback is read-only and isolated; model choices belong to their endpoint")
        var moment: Double = 0, firstChineseAt: Double?; var gate: CheckedContinuation<String,Never>?
        let timeline = ReplyPipeline { _ in await withCheckedContinuation { gate = $0 } }
        timeline.onTranslation = { _,_,_,_ in if firstChineseAt == nil { firstChineseAt = moment } }
        timeline.observe(conversation:"timeline",messages:[.init(ordinal:2,author:.assistant,text:"Phase A",segment:1)],responseComplete:false,now:0)
        moment = 3; timeline.tick(now:moment); try await settle { gate != nil }
        moment = 3.2; gate?.resume(returning:"阶段 A 中文"); gate = nil
        try await settle { firstChineseAt != nil }
        precondition(firstChineseAt == 3.2 && firstChineseAt! < 12 && timeline.completedTurns == 0)
        moment = 12; timeline.observe(conversation:"timeline",messages:[.init(ordinal:2,author:.assistant,text:"Phase A",segment:1),.init(ordinal:2,author:.assistant,text:"Phase B",segment:2)],responseComplete:false,now:12)
        moment = 15; timeline.tick(now:moment); try await settle { gate != nil }; gate?.resume(returning:"阶段 B 中文"); gate = nil
        try await settle { !timeline.busy }; timeline.observe(conversation:"timeline",messages:[.init(ordinal:2,author:.assistant,text:"Phase A",segment:1),.init(ordinal:2,author:.assistant,text:"Phase B",segment:2)],responseComplete:true,now:36)
        precondition(timeline.completedTurns == 2)
        print("PASS: virtual A Chinese is visible at 3.2 seconds, before B at 12 and whole-turn completion at 36")
        var calls = 0, results = 0
        let limited = ReplyPipeline { text in calls += 1; if calls == 1 { throw ServiceCooldown(seconds:10) }; return text }
        limited.onTranslation = {_,_,_,_ in results += 1}
        limited.submit(.init(candidate:.init(ordinal:2,text:"limited"),conversation:"limits",manual:true),now:0)
        try await settle { calls == 1 && !limited.busy }; limited.tick(now:9); await Task.yield(); precondition(calls == 1)
        limited.tick(now:10); try await settle { results == 1 }
        precondition(ServiceCooldown.duration("120") == 120 && ServiceCooldown.duration("bad") == 60)
        print("PASS: service Retry-After pauses only translation requests and resumes without losing source")
        var cancelGate: CheckedContinuation<String,Never>?
        let cancel = ReplyPipeline { _ in await withCheckedContinuation {cancelGate=$0} }
        cancel.submit(.init(candidate:.init(ordinal:2,text:"cancelled"),conversation:"cancel",manual:true),now:0)
        try await settle { cancelGate != nil }; cancel.suspend(); cancelGate?.resume(returning:"late"); cancelGate = nil
        cancel.tick(now:30); await Task.yield(); precondition(!cancel.busy && cancel.hasFailures)
        cancel.clear(); limited.clear(); timeline.clear()
        print("PASS: explicit cancellation stays suspended until retry, instead of restarting on the next poll")
        let usage = ClaudeUsageMonitor(settings:prefs,load:{_,_ in preconditionFailure("No legacy credentials after migration")},enabled:{false})
        var evidence = try UsageEvidence.statusLine(Data(#"{"rate_limits":{"seven_day":{"used_percentage":25}}}"#.utf8),binding:"cli-approved")
        evidence.identity = .init(fingerprint: String(repeating: "a", count: 64), displayName: "Synthetic account")
        evidence.epoch = "fixture-epoch"; evidence.sequence = 1
        usage.receive(evidence); try usage.migrateVisible(account:"Synthetic account")
        precondition(!prefs.bool(forKey:"usageConnected") && prefs.data(forKey:"visibleUsageConnection") != nil)
        let restored = ClaudeUsageMonitor(settings:prefs,load:{_,_ in preconditionFailure("No hidden fallback")},enabled:{false})
        restored.refresh(); precondition(restored.source == .statusLine && restored.accountLabel == "Synthetic account" && restored.snapshot == nil)
        restored.receive(evidence); let previous = restored.snapshot
        restored.receive(try UsageEvidence.statusLine(Data(#"{"rate_limits":{"seven_day":{"used_percentage":99}}}"#.utf8),binding:"cli-other"))
        precondition(restored.snapshot == previous)
        usage.stop(); restored.stop()
        print("PASS: visible-source migration restores one atomic binding, disables legacy rollback, and isolates other accounts")
        for saved in [#"{"source":"unknown","account":"Synthetic","binding":"cli-approved"}"#, #"{"source":"desktop","account":"Synthetic","binding":"cli-approved"}"#, #"{"source":"statusLine","account":"","binding":"cli-approved"}"#, "broken-json"] {
            prefs.set(Data(saved.utf8), forKey:"visibleUsageConnection"); prefs.set(true,forKey:"usageConnected")
            let corrupt = ClaudeUsageMonitor(settings:prefs,load:{_,_ in preconditionFailure("Corrupt visible configuration must never load legacy credentials")},enabled:{true})
            corrupt.refresh()
            precondition(!corrupt.refreshing && !prefs.bool(forKey:"usageConnected") && corrupt.status.contains("配置"))
            corrupt.stop()
        }
        print("PASS: malformed visible-source preferences fail closed without legacy credential fallback")
        _ = NSApplication.shared
        let scroll = LongMessageReader.makeScrollView(), body = scroll.documentView as! NSTextView
        LongMessageReader.updateText(scroll,text:"abcdefghij",original:false);body.setSelectedRange(.init(location:5,length:3))
        LongMessageReader.updateText(scroll,text:"HEADabcdefghij",original:false)
        precondition(body.selectedRange() == NSRange(location:9,length:3))
        print("PASS: selection follows unchanged text when preceding content is inserted")
        print("7 optimization lifecycle contracts passed")
    }
}
