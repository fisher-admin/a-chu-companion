import AppKit
import SwiftUI

struct GlassBackground: NSViewRepresentable {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        view.alphaValue = reduceTransparency ? 1 : 0.92
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.alphaValue = reduceTransparency ? 1 : 0.92
    }
}
