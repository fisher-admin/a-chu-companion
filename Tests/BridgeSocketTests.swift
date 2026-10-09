import Foundation

@main struct BridgeSocketTests {
    @MainActor static func main() async throws {
        let server = LocalBridge(); var decoder = BridgeDecoder(); var originals = 0
        let parent = URL(fileURLWithPath: "/tmp").appendingPathComponent("achu-socket-test-" + String(UUID().uuidString.prefix(8)))
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let sentinel = parent.appendingPathComponent("keep.txt"); try Data("keep".utf8).write(to: sentinel)
        defer { server.stop(); try? FileManager.default.removeItem(at: parent) }
        try server.start(directory: parent) { data in
            await MainActor.run {
                do { let value = try decoder.accept(data, token: server.token); if value.snapshot != nil { originals += 1 }; return true }
                catch { return false }
            }
        }
        let connection = server.connectionFile!
        let permissions = try FileManager.default.attributesOfItem(atPath: connection.path)[.posixPermissions] as! NSNumber
        precondition(permissions.intValue == 0o600)
        let path = connection.path
        server.requestWebUsage(binding: "web-socketfixture", url: "https://claude.ai/chat/synthetic")
        let status = try await Task.detached {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = ["Tests/BridgeSocketClient.py", path]
            try process.run(); process.waitUntilExit(); return process.terminationStatus
        }.value
        precondition(status == 0 && originals == 1)
        server.stop()
        precondition(!FileManager.default.fileExists(atPath: connection.path) && FileManager.default.fileExists(atPath: sentinel.path))
        print("PASS: connection permissions, acknowledgement, safe shutdown and caller-owned files are preserved")
        let publication = parent.appendingPathComponent("stable/connection.json")
        try server.start(directory: parent, publication: publication) { _ in true }
        let firstToken = server.token
        server.stop()
        precondition(!FileManager.default.fileExists(atPath: publication.path))
        try server.start(directory: parent, publication: publication) { _ in true }
        precondition(server.token != firstToken && server.connectionFile == publication)
        let replacement = LocalBridge()
        defer { replacement.stop() }
        try replacement.start(directory: parent, publication: publication) { _ in true }
        let replacementToken = replacement.token
        server.stop()
        let value = try JSONSerialization.jsonObject(with: Data(contentsOf: publication)) as! [String: Any]
        precondition(value["token"] as? String == replacementToken)
        replacement.stop()
        precondition(!FileManager.default.fileExists(atPath: publication.path) && FileManager.default.fileExists(atPath: sentinel.path))
        print("PASS: stable discovery path rotates its token on restart and old shutdown preserves a replacement's publication")
        print("4 socket integration contracts passed")
    }
}
