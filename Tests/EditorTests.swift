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
        let reader = LongMessageReader.makeScrollView()
        let body = reader.documentView as! NSTextView
        let long = String(repeating: "完整的超长中文段落。\n", count: 12_000) + "COMPLETE-END"
        body.string = long
        precondition(body.string == long && body.string.hasSuffix("COMPLETE-END") && !body.isEditable && body.isSelectable)
        print("PASS: native long message reader retains the entire >100k body without editable or giant SwiftUI text")
        precondition(reader.scrollerStyle == .legacy && !reader.autohidesScrollers && reader.hasVerticalScroller)
        print("PASS: long-message vertical scrollbar remains visible")
        reader.contentView.scroll(to: NSPoint(x: 0, y: 200))
        let position = reader.contentView.bounds.origin
        LongMessageReader.updateText(reader, text: long, original: false)
        precondition(reader.contentView.bounds.origin == position)
        print("PASS: unchanged long text preserves the reading position")
        LongMessageReader.updateText(reader, text: "中文头部。\n" + long, original: false)
        precondition(reader.contentView.bounds.origin.y == 0 && body.string.hasPrefix("中文头部。"))
        print("PASS: changed long text returns to the beginning and keeps the full body")
        for size: CGFloat in [12, 14, 16] {
            LongMessageReader.updateText(reader, text: body.string, original: false, fontSize: size)
            precondition(body.font?.pointSize == size && body.string.hasSuffix("COMPLETE-END"))
        }
        LongMessageReader.updateText(reader, text: body.string, original: true, fontSize: 16)
        precondition(body.font?.pointSize == 12)
        print("PASS: all three Chinese font sizes preserve the full body while originals retain their own size")
        print("9 native editor tests passed")
    }
}
