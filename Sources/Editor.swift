import AppKit
import SwiftUI

final class DraftTextView: NSTextView {
    var onSubmit: () -> Void = {}
    override func keyDown(with event: NSEvent) {
        if InputPolicy.shouldSubmit(returnKey: event.keyCode == 36 || event.keyCode == 76,
                                    shift: event.modifierFlags.contains(.shift), composing: hasMarkedText()) {
            if isEditable { onSubmit() }
            return
        }
        super.keyDown(with: event)
    }
}

struct DraftEditor: NSViewRepresentable {
    @Binding var text: String
    let enabled: Bool
    let submit: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let view = DraftTextView()
        view.isRichText = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.drawsBackground = false
        view.font = .systemFont(ofSize: 16)
        view.textColor = .labelColor
        view.textContainerInset = NSSize(width: 12, height: 12)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
        view.delegate = context.coordinator
        view.setAccessibilityLabel("中文内容")
        view.setAccessibilityIdentifier("chinese-draft")
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? DraftTextView else { return }
        if view.string != text && !view.hasMarkedText() { view.string = text }
        view.isEditable = enabled
        view.onSubmit = submit
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DraftEditor
        init(_ parent: DraftEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }
}
