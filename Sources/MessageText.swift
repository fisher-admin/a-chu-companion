import AppKit
import SwiftUI

struct MessageText: View {
    let text: String
    var original = false
    var fontSize: CGFloat = 14
    var body: some View {
        if text.count > 8_000 {
            VStack(alignment: .leading, spacing: 6) {
                LongMessageReader(text: text, original: original, fontSize: fontSize).frame(height: 260)
                HStack {
                    Text("\(text.count.formatted()) 字 · 滚动查看全文").foregroundStyle(.secondary)
                    Spacer()
                    Button("复制全文") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }.buttonStyle(.plain)
                }.font(.system(size: 10))
            }
        } else {
            Text(text).font(.system(size: original ? 12 : fontSize))
                .foregroundStyle(original ? .secondary : .primary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct LongMessageReader: NSViewRepresentable {
    let text: String
    let original: Bool
    var fontSize: CGFloat = 14
    static func updateText(_ scroll: NSScrollView, text: String, original: Bool, fontSize: CGFloat = 14) {
        guard let view = scroll.documentView as? NSTextView else { return }
        let font = NSFont.systemFont(ofSize: original ? 12 : fontSize)
        let color: NSColor = original ? .secondaryLabelColor : .labelColor
        if view.font != font { view.font = font }
        if view.textColor != color { view.textColor = color }
        if view.string != text {
            view.string = text
            if let container = view.textContainer { view.layoutManager?.ensureLayout(for: container) }
            view.scrollRangeToVisible(NSRange(location: 0, length: 0))
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
    static func makeScrollView() -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 260))
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .legacy
        scroll.autohidesScrollers = false
        scroll.drawsBackground = false
        let view = NSTextView(frame: scroll.contentView.bounds)
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 2, height: 4)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        view.setAccessibilityLabel("消息全文")
        scroll.documentView = view
        return scroll
    }
    func makeNSView(context: Context) -> NSScrollView { Self.makeScrollView() }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 500, height: proposal.height ?? 260)
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        Self.updateText(scroll, text: text, original: original, fontSize: fontSize)
    }
}
