import Foundation

@main struct PermissionTests {
    @MainActor static func main() async {
        var granted = false
        var checks = 0
        var changes: [Bool] = []
        let monitor = AccessibilityPermissionMonitor(check: { checks += 1; return granted }, interval: 10_000_000)
        monitor.onChange = { changes.append($0) }
        monitor.start()
        precondition(changes == [false], "Initial denied state must be delivered")
        print("PASS: initial permission state delivered immediately")

        granted = true
        await waitUntil { changes == [false, true] }
        precondition(changes == [false, true], "Grant must be detected without activation, refresh or restart")
        print("PASS: grant detected automatically without app activation")

        let count = changes.count
        try! await Task.sleep(nanoseconds: 50_000_000)
        precondition(changes.count == count, "Unchanged permission must not emit duplicate events")
        print("PASS: unchanged permission does not repeat notifications")

        granted = false
        await waitUntil { changes == [false, true, false] }
        precondition(changes == [false, true, false], "Revocation must also be detected")
        print("PASS: revocation detected automatically")

        monitor.stop()
        let stoppedChecks = checks
        granted = true
        try! await Task.sleep(nanoseconds: 50_000_000)
        precondition(checks == stoppedChecks && changes.last == false, "Stopped monitor must not continue polling")
        print("PASS: stopped monitor performs no further checks")

        monitor.start()
        precondition(changes.last == true, "Restart must immediately reconcile current permission")
        granted = false
        await waitUntil { changes.last == false }
        precondition(changes.last == false)
        monitor.stop()
        print("PASS: restarted monitor resumes observing changes")
        var modelGranted = false
        let model = TranslatorModel(permissionCheck: { modelGranted }, permissionInterval: 10_000_000)
        model.input = "保留中文草稿"
        model.output = "Keep the draft."
        model.history = [.init(id: "existing", isUser: true, chinese: "原消息", foreign: "Existing message.")]
        modelGranted = true
        await waitUntil { model.permission }
        precondition(model.permission && model.status.contains("辅助功能已开启"), "Model must publish the grant and replace the obsolete permission hint")
        precondition(!model.hasTarget, "Grant must not capture a target or initiate sending")
        print("PASS: model immediately reflects grant without capturing or sending")
        precondition(model.input == "保留中文草稿" && model.output == "Keep the draft." && model.history.count == 1,
                     "Permission refresh must preserve the draft, translation and history")
        print("PASS: permission changes preserve current chat and draft")

        model.busy = true
        model.report("正在处理…")
        modelGranted = false
        await waitUntil { !model.permission }
        precondition(!model.permission)
        modelGranted = true
        await waitUntil { model.permission }
        precondition(model.permission && model.busy && model.status == "正在处理…", "Grant must not overwrite an active job")
        print("PASS: busy job status is preserved through permission changes")
        model.stopPermissionMonitoring()
        modelGranted = false
        try! await Task.sleep(nanoseconds: 50_000_000)
        precondition(model.permission, "Model must stop polling at shutdown")
        print("PASS: model shutdown stops permission monitoring")
        print("10 permission tests passed")
    }

    @MainActor static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try! await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
