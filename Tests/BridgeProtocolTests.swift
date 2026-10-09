import Foundation

@main struct BridgeProtocolTests {
    @MainActor static func main() throws {
        var decoder = BridgeDecoder()
        func frame(_ payload: [String:Any]) throws -> Data { try JSONSerialization.data(withJSONObject: payload) }
        var base: [String:Any] = ["version":1,"token":"synthetic-token","kind":"delta","binding":"cli-fixture","epoch":"one","messageID":"message","turnID":"turn","sequence":0,"text":"first\n","final":false]
        let first = try decoder.accept(frame(base), token: "synthetic-token")
        precondition(first.snapshot?.messages.last?.text == "first\n" && first.snapshot?.responseComplete == false)
        precondition(try! decoder.accept(frame(base), token: "synthetic-token").duplicate)
        base["sequence"] = 20
        precondition(try! decoder.accept(frame(base), token: "synthetic-token").needsSync)
        base["sequence"] = 1; base["text"] = ""; base["final"] = true
        let final = try decoder.accept(frame(base), token: "synthetic-token")
        precondition(final.snapshot?.messages.last?.completed == true && final.snapshot?.responseComplete == false)
        print("PASS: CLI delta ordering, replay, gaps and empty final preserve message versus turn completion")
        var race = BridgeDecoder()
        var reversed: [String:Any] = ["version":1,"token":"synthetic-token","kind":"delta","binding":"cli-race","epoch":"race-one","messageID":"race-message","turnID":"turn","sequence":1,"text":"tail","final":true]
        let buffered = try race.accept(frame(reversed),token:"synthetic-token")
        precondition(!buffered.needsSync && buffered.snapshot == nil, "a simultaneous later batch must wait without being rejected or published")
        precondition(try! race.accept(frame(reversed),token:"synthetic-token").duplicate, "buffered duplicates must not append twice")
        reversed["text"] = "conflict"
        precondition(try! race.accept(frame(reversed),token:"synthetic-token").needsSync, "conflicting duplicate batches must not replace queued data")
        reversed["sequence"] = 0; reversed["text"] = "head "; reversed["final"] = false
        let ordered = try race.accept(frame(reversed),token:"synthetic-token")
        precondition(ordered.snapshot?.messages.last?.text == "head tail" && ordered.snapshot?.messages.last?.completed == true, "earlier arrival must drain the complete original in sequence")
        precondition(try! race.accept(frame(reversed),token:"synthetic-token").duplicate)
        print("PASS: concurrent CLI batches, replay and conflicting duplicates preserve the complete original")
        var hole = BridgeDecoder()
        reversed["messageID"] = "missing-middle"; reversed["sequence"] = 2; reversed["text"] = "last"; reversed["final"] = true
        precondition(try! hole.accept(frame(reversed),token:"synthetic-token").snapshot == nil)
        reversed["sequence"] = 0; reversed["text"] = "first "; reversed["final"] = false
        let partial = try hole.accept(frame(reversed),token:"synthetic-token")
        precondition(partial.snapshot?.messages.last?.text == "first " && partial.snapshot?.messages.last?.completed == false, "missing middle text cannot be guessed or marked complete")
        reversed["sequence"] = 1; reversed["text"] = "middle "
        let filled = try hole.accept(frame(reversed),token:"synthetic-token")
        precondition(filled.snapshot?.messages.last?.text == "first middle last" && filled.snapshot?.messages.last?.completed == true)
        print("PASS: missing middle batches remain incomplete until the actual content arrives")
        var limited = BridgeDecoder()
        reversed["sequence"] = 9; reversed["messageID"] = "far-gap"
        precondition(try! limited.accept(frame(reversed),token:"synthetic-token").needsSync)
        reversed["sequence"] = 1
        for index in 0..<32 {
            reversed["messageID"] = "queued-\(index)"
            precondition(try! limited.accept(frame(reversed),token:"synthetic-token").snapshot == nil)
        }
        reversed["messageID"] = "over-capacity"
        precondition(try! limited.accept(frame(reversed),token:"synthetic-token").needsSync)
        print("PASS: CLI reorder distance and pending-frame count are bounded")
        let emptyUsage: [String:Any] = ["version":1,"token":"synthetic-token","kind":"usage","binding":"cli-startup","epoch":"startup","sequence":0,"usage":["rate_limits":[:]]]
        let unknown = try decoder.accept(frame(emptyUsage),token:"synthetic-token")
        precondition(unknown.evidence == nil && !unknown.needsSync, "CLI startup without quota fields is unknown, not a malformed connection or fake zero")
        print("PASS: absent startup quota fields do not invent usage or reject a valid connection")
        base["token"] = "wrong"
        do { _ = try decoder.accept(frame(base), token: "synthetic-token"); fatalError("unauthorized") } catch {}
        base["token"] = "synthetic-token"; base["readKey"] = true
        do { _ = try decoder.accept(frame(base), token: "synthetic-token"); fatalError("unknown command") } catch {}
        print("PASS: bridge rejects unauthorized tokens and high-privilege or unknown fields")
        let web: [String:Any] = ["version":1,"token":"synthetic-token","kind":"snapshot","binding":"web-fixture","epoch":"page-one","sequence":0,"url":"https://claude.ai/chat/synthetic","messages":[["ordinal":2,"author":"assistant","segment":0,"text":"formal reply","completed":false]],"final":false]
        precondition(try! decoder.accept(frame(web), token: "synthetic-token").snapshot?.messages.last?.text == "formal reply")
        var hostile = web; hostile["url"] = "https://evil.example/chat/synthetic"
        do { _ = try decoder.accept(frame(hostile), token: "synthetic-token"); fatalError("origin") } catch {}
        print("PASS: browser snapshots are constrained to the intended website")
        var nextPage = web; nextPage["epoch"] = "page-two"
        _ = try decoder.accept(frame(nextPage), token: "synthetic-token")
        precondition(try! decoder.accept(frame(web), token: "synthetic-token").duplicate, "retired page epochs must not replace a current page")
        var number = nextPage; number["sequence"] = true
        do { _ = try decoder.accept(frame(number), token: "synthetic-token"); fatalError("boolean index") } catch {}
        number["sequence"] = 1.5
        do { _ = try decoder.accept(frame(number), token: "synthetic-token"); fatalError("fractional index") } catch {}
        print("PASS: retired page epochs and noninteger sequence values are rejected")
        var invalid = nextPage; invalid["epoch"] = "invalid-page"; invalid["final"] = 1
        do { _ = try decoder.accept(frame(invalid), token:"synthetic-token"); fatalError("integer final") } catch {}
        nextPage["sequence"] = 1
        precondition(try! decoder.accept(frame(nextPage),token:"synthetic-token").snapshot != nil)
        print("PASS: invalid epochs do not poison the current stream and boolean fields are strict")
        var quotas = BridgeDecoder()
        var quota: [String: Any] = ["version":1,"token":"synthetic-token","kind":"usage","binding":"web-account","epoch":"account-a","sequence":1,"url":"https://claude.ai/settings/usage","usage":["rate_limits":["seven_day":["used_percentage":25]]]]
        _ = try quotas.accept(frame(quota), token: "synthetic-token")
        quota["epoch"] = "account-b"; quota["sequence"] = 1
        _ = try quotas.accept(frame(quota), token: "synthetic-token")
        quota["epoch"] = "account-a"; quota["sequence"] = 9
        precondition(try! quotas.accept(frame(quota), token: "synthetic-token").duplicate, "late quota generations must not replace the current account")
        print("PASS: late quota generations cannot overwrite the current source")
        quota["epoch"] = "account-b"; quota["sequence"] = 2
        quota["account"] = ["fingerprint": String(repeating: "b", count: 64), "displayName": "Synthetic B"]
        let checkedQuota = try quotas.accept(frame(quota), token: "synthetic-token")
        precondition(checkedQuota.evidence?.identity?.displayName == "Synthetic B")
        precondition(try! quotas.accept(frame(quota), token: "synthetic-token").duplicate)
        quota["sequence"] = 3; quota["usage"] = ["rate_limits": [:]]; quota.removeValue(forKey: "account")
        let missingIdentity = try quotas.accept(frame(quota), token: "synthetic-token")
        precondition(missingIdentity.evidence == nil && missingIdentity.accountObservation?.identity == nil && missingIdentity.accountObservation != nil)
        quota["sequence"] = 4; quota["account"] = ["fingerprint": String(repeating: "b", count: 64), "displayName": "B", "email": "synthetic@example.test"]
        do { _ = try quotas.accept(frame(quota), token: "synthetic-token"); fatalError("raw identity fields are forbidden") } catch {}
        print("PASS: current account identity is explicit, empty usage invalidates identity and raw account fields are rejected")
        var labeled = emptyUsage
        labeled["binding"] = "cli-labeled"; labeled["source"] = ["workspace":"Synthetic project","model":"Opus"]
        let labelAccepted: Bool
        do { _ = try decoder.accept(frame(labeled),token:"synthetic-token"); labelAccepted = true }
        catch { labelAccepted = false }
        precondition(labelAccepted, "a bounded CLI source summary must not discard a valid usage report")
        print("PASS: valid CLI source labels accompany usage without changing reply content")
        labeled["sequence"] = 1; labeled["source"] = ["workspace":"/private/project"]
        do { _ = try decoder.accept(frame(labeled),token:"synthetic-token"); fatalError("full source path") } catch {}
        labeled["source"] = ["workspace":"project","accountEmail":"private@example.test"]
        do { _ = try decoder.accept(frame(labeled),token:"synthetic-token"); fatalError("raw source account") } catch {}
        labeled["source"] = ["workspace":"project\nother"]
        do { _ = try decoder.accept(frame(labeled),token:"synthetic-token"); fatalError("source control") } catch {}
        labeled["source"] = ["workspace":"project"]; labeled["sequence"] = 1
        _ = try decoder.accept(frame(labeled),token:"synthetic-token")
        print("PASS: invalid source paths, extra fields and controls do not poison the following valid report")
        print("13 bridge protocol contracts passed")
    }
}
