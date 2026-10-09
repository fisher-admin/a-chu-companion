import AppKit
import Foundation

enum UsageAcquisition {
    static func webSetupError(bundle: String?, supportDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")) -> String? {
        let folders: [String]
        switch bundle {
        case "com.google.Chrome": folders = ["Google/Chrome"]
        case "com.microsoft.edgemac": folders = ["Microsoft Edge"]
        case nil: folders = ["Google/Chrome", "Microsoft Edge"]
        default: return "当前浏览器尚未提供网页额度入口；回复读取与发送可以继续。现有额度入口支持 Chrome 和 Edge。"
        }
        for folder in folders {
            let manifest = supportDirectory.appendingPathComponent(folder + "/NativeMessagingHosts/local.achu.companion.json")
            guard FileManager.default.fileExists(atPath: manifest.path) else { continue }
            guard let data = try? Data(contentsOf: manifest), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  value["name"] as? String == "local.achu.companion", value["type"] as? String == "stdio",
                  let path = value["path"] as? String, path.hasPrefix("/"), FileManager.default.fileExists(atPath: path),
                  let origins = value["allowed_origins"] as? [String], origins.count == 1,
                  origins[0].range(of: "^chrome-extension://[a-p]{32}/$", options: .regularExpression) != nil else {
                return "网页额度入口配置已失效，请在「连接额度 → 网页端」重新连接网页入口；回复读取与发送可以继续。"
            }
            return nil
        }
        return "网页额度入口未配置，请在「连接额度 → 网页端」配置并启用网页入口；回复读取与发送可以继续。"
    }
    static var cliDirectory: URL {
        let override = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
        return override.map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }
    static var bridgeScript: URL? { Bundle.main.resourceURL?.appendingPathComponent("Bridge/bridge.py") }
    static func run(_ action: String, connection: String? = nil) async throws {
        guard ["install-cli", "request-cli", "uninstall-cli"].contains(action), let script = bridgeScript,
              FileManager.default.fileExists(atPath: script.path) else { throw BridgeError.message("找不到已安装的额度入口，请重新安装伴侣。") }
        var arguments = ["python3", script.path, "--" + action, "--config-dir", cliDirectory.path]
        if let connection { arguments += ["--connection", connection] }
        try await execute(arguments)
    }
    static func installWeb(extensionID: String, browser: String, connection: String) async throws {
        guard extensionID.range(of: "^[a-p]{32}$", options: .regularExpression) != nil,
              let script = bridgeScript, ["Chrome", "Edge"].contains(browser), !connection.isEmpty else {
            throw BridgeError.message("请填写网页入口的32位扩展ID，并先开启只读入口。")
        }
        let folder = browser == "Chrome" ? "Google/Chrome" : "Microsoft Edge"
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/" + folder + "/NativeMessagingHosts")
        try await execute(["python3", script.path, "--install-native", "--output-dir", directory.path, "--extension-id", extensionID, "--connection", connection])
    }
    private static func execute(_ args: [String]) async throws {
        try await Task.detached {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env"); process.arguments = args
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            process.environment = environment
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run()
            let deadline = Date().addingTimeInterval(10)
            while process.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
            if process.isRunning { process.terminate(); throw BridgeError.message("CLI 入口操作超时，请检查 Claude Code 配置。") }
            guard process.terminationStatus == 0 else { throw BridgeError.message("CLI 入口未完成。请先配置入口；若状态栏被修改，先保留现有配置并移除旧入口后再安装。") }
        }.value
    }
    @MainActor static func openWebUsage() { NSWorkspace.shared.open(URL(string: "https://claude.ai/new#settings/usage")!) }
    @MainActor static func revealWebAdapter() {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Bridge/chrome") else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
