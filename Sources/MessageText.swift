import AppKit
import SwiftUI

extension Notification.Name { static let achuReaderInteracted = Notification.Name("achuReaderInteracted") }
private final class ReadingTextView: NSTextView {
    override func mouseDown(with event: NSEvent) {
        NotificationCenter.default.post(name: .achuReaderInteracted, object: nil)
        super.mouseDown(with: event)
    }
}
private final class ReadingScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        NotificationCenter.default.post(name: .achuReaderInteracted, object: nil)
        super.scrollWheel(with: event)
    }
}
struct MessageText: View {
    let text: String
    var original = false
    var fontSize: CGFloat = 14
    var body: some View {
        let blocks = MarkdownTable.blocks(text)
        if blocks.contains(where: { if case .table = $0 { return true }; return false }) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let value):
                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { ProseMessageText(text: trimmed, original: original, fontSize: fontSize) }
                    case .table(let table): TableMessageText(table: table, original: original, fontSize: fontSize)
                    }
                }
            }
        } else { ProseMessageText(text: text, original: original, fontSize: fontSize) }
    }
}

private struct TableMessageText: View {
    let table: MarkdownTable
    let original: Bool
    let fontSize: CGFloat
    private func alignment(_ column: Int) -> Alignment {
        switch table.alignments[column] {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
    private func cell(_ text: String, column: Int, header: Bool) -> some View {
        Text(MarkdownTable.displayCell(text))
            .font(.system(size: original ? 12 : fontSize, weight: header ? .semibold : .regular))
            .foregroundStyle(original ? .secondary : .primary)
            .textSelection(.enabled)
            .frame(width: 116, alignment: alignment(column))
            .fixedSize(horizontal: false, vertical: true)
            .padding(8)
            .frame(maxHeight: .infinity)
            .background(header ? Color.primary.opacity(0.07) : Color.clear)
            .overlay(Rectangle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal) {
                Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        ForEach(table.headers.indices, id: \.self) { column in cell(table.headers[column], column: column, header: true) }
                    }
                    ForEach(table.rows.indices, id: \.self) { row in
                        GridRow {
                            ForEach(table.headers.indices, id: \.self) { column in cell(table.rows[row][column], column: column, header: false) }
                        }
                    }
                }
                .padding(1)
            }
            .accessibilityLabel("表格：\(table.headers.count) 列，\(table.rows.count) 行数据")
            HStack {
                Text("\(table.headers.count) 列 · \(table.rows.count) 行").foregroundStyle(.secondary)
                Spacer()
                Button("复制表格") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(table.source, forType: .string)
                }.buttonStyle(.plain).accessibilityLabel(original ? "复制原文表格" : "复制中文表格")
            }.font(.system(size: 10))
        }
    }
}

private struct ProseMessageText: View {
    let text: String
    let original: Bool
    let fontSize: CGFloat
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
            let firstDisplay = view.string.isEmpty
            let position = scroll.contentView.bounds.origin
            let selections = view.selectedRanges
            let before = Array(view.string.utf16), after = Array(text.utf16)
            var prefix = 0; while prefix < min(before.count, after.count), before[prefix] == after[prefix] { prefix += 1 }
            var suffix = 0; while suffix < min(before.count, after.count) - prefix, before[before.count - suffix - 1] == after[after.count - suffix - 1] { suffix += 1 }
            func positionAfterEdit(_ offset: Int) -> Int {
                if offset <= prefix { return offset }
                if offset >= before.count - suffix { return offset + after.count - before.count }
                return min(offset, after.count - suffix)
            }
            view.string = text
            if let container = view.textContainer { view.layoutManager?.ensureLayout(for: container) }
            let length = (text as NSString).length
            view.selectedRanges = selections.map { value in
                let range = value.rangeValue
                let start = min(max(0, positionAfterEdit(range.location)), length)
                let end = min(max(start, positionAfterEdit(NSMaxRange(range))), length)
                return NSValue(range: NSRange(location: start, length: end - start))
            }
            if firstDisplay { view.scrollRangeToVisible(NSRange(location: 0, length: 0)) }
            scroll.contentView.scroll(to: firstDisplay ? .zero : position)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
    static func makeScrollView() -> NSScrollView {
        let scroll = ReadingScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 260))
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .legacy
        scroll.autohidesScrollers = false
        scroll.drawsBackground = false
        let view = ReadingTextView(frame: scroll.contentView.bounds)
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
