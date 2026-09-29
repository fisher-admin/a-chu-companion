import AppKit

@main struct EditorTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let view = DraftTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 200))
        view.isRichText = false
        var submissions = 0
        view.onSubmit = { submissions += 1 }
        func event(_ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                            windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                            isARepeat: false, keyCode: 36)!
        }
        view.string = "你好"
        view.keyDown(with: event())
        precondition(submissions == 1, "Return must submit once")
        print("PASS: native Return submits once")
        view.keyDown(with: event(.shift))
        precondition(submissions == 1 && view.string.contains("\n"), "Shift Return must add newline")
        print("PASS: native Shift Return adds newline")
        view.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        precondition(view.hasMarkedText())
        view.keyDown(with: event())
        precondition(submissions == 1, "IME Return must not submit")
        print("PASS: real marked text blocks submit")
        view.unmarkText()
        view.isEditable = false
        view.keyDown(with: event())
        precondition(submissions == 1, "busy editor must not submit")
        print("PASS: disabled editor blocks duplicate submit")
        print("4 native editor tests passed")
    }
}
