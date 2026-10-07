import Foundation

@main struct StageReplayTests {
    @MainActor static func settle(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() { precondition(ContinuousClock.now < deadline); try await Task.sleep(for: .milliseconds(5)) }
    }
    @MainActor static func main() async throws {
        var requests: [String] = [], outputs: [String] = []
        var first: CheckedContinuation<String,Never>?
        let queue = ReplyPipeline { text in
            requests.append(text)
            if requests.count == 1 { return await withCheckedContinuation { first = $0 } }
            return "中:" + text
        }
        queue.onTranslation = { _,_,text,_ in outputs.append(text) }
        let long = "long first paragraph.\n\nlong second paragraph.\n\nlong final paragraph."
        queue.observe(conversation:"fairness",messages:[.init(ordinal:2,author:.assistant,text:long,segment:1)],responseComplete:false,now:0)
        queue.tick(now:3); try await settle { first != nil }
        queue.observe(conversation:"fairness",messages:[.init(ordinal:2,author:.assistant,text:long,segment:1),.init(ordinal:2,author:.assistant,text:"new stable stage",segment:2)],responseComplete:false,now:3)
        queue.tick(now:6); first?.resume(returning:"首块中文"); first = nil
        try await settle { requests.count >= 4 && !queue.busy }
        precondition(requests[1] == "new stable stage" && outputs.first == "首块中文\n\n" && outputs.contains { $0.hasPrefix("首块中文") && $0.contains("long final") })
        print("PASS: a new stable stage gets a turn between a previous long reply's slices; each slice publishes immediately")
        var count = 0
        let completeOnly = ReplyPipeline(incremental:false) { text in count += 1; return text }
        completeOnly.observe(conversation:"fallback",messages:[.init(ordinal:2,author:.assistant,text:"unfinished")],responseComplete:false,now:0)
        completeOnly.tick(now:30); await Task.yield(); precondition(count == 0)
        completeOnly.observe(conversation:"fallback",messages:[.init(ordinal:2,author:.assistant,text:"unfinished",completed:true)],responseComplete:true,now:36)
        try await settle { count == 1 && !completeOnly.busy }
        print("PASS: the explicit fallback waits for a complete formal message")
        @MainActor func replay() async throws -> String {
            var state: UInt64 = 61434; var result = ""
            let pipeline = ReplyPipeline { "中:" + $0 }
            pipeline.onTranslation = { _,_,value,_ in result = value }
            let final = "Deterministic paragraph.\n\nSecond paragraph 😀."
            var length = 0, time: Double = 0
            while length < final.count {
                state = state &* 6364136223846793005 &+ 1
                length = min(final.count,length + Int(state % 7) + 1); time += 0.25
                pipeline.observe(conversation:"replay",messages:[.init(ordinal:2,author:.assistant,text:String(final.prefix(length)))],responseComplete:false,now:time)
                await Task.yield()
            }
            pipeline.observe(conversation:"replay",messages:[.init(ordinal:2,author:.assistant,text:final,completed:true)],responseComplete:true,now:time+1)
            try await settle { !pipeline.busy && !result.isEmpty }; pipeline.clear(); return result
        }
        let one = try await replay(), two = try await replay()
        precondition(one == two && one.hasSuffix("Second paragraph 😀."))
        queue.clear(); completeOnly.clear()
        print("PASS: identical seeded streaming replays produce identical complete Chinese without duplicate tails")
        print("3 stage replay contracts passed")
    }
}
