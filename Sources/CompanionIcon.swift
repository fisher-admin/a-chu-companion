import AppKit

enum CompanionIcon {
    // Sampled in sRGB from the installed Claude 2.19675.0 app icon:
    // its orange tile is deeper toward the bottom; #D9704E is the median.
    private static let orange = NSColor(srgbRed: 217.0 / 255, green: 112.0 / 255, blue: 78.0 / 255, alpha: 1)
    private static let orangeTop = NSColor(srgbRed: 217.0 / 255, green: 119.0 / 255, blue: 87.0 / 255, alpha: 1)
    private static let orangeBottom = NSColor(srgbRed: 219.0 / 255, green: 105.0 / 255, blue: 68.0 / 255, alpha: 1)
    private static let face = NSColor(srgbRed: 250.0 / 255, green: 249.0 / 255, blue: 245.0 / 255, alpha: 1)
    static func image(size: CGFloat, template: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(in: rect, template: template)
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = "A畜伴侣：猪头中央的 A"
        return image
    }

    static func draw(in rect: NSRect, template: Bool) {
        NSGraphicsContext.saveGraphicsState()
        let transform = AffineTransform(scaleByX: rect.width / 1024, byY: rect.height / 1024)
        (transform as NSAffineTransform).concat()
        if !template {
            let tile = NSBezierPath(roundedRect: NSRect(x: 8, y: 8, width: 1008, height: 1008), xRadius: 222, yRadius: 222)
            NSGradient(starting: orangeTop, ending: orangeBottom)!.draw(in: tile, angle: -90)
        }
        (template ? NSColor.black : face).setFill()
        let leftEar = NSBezierPath()
        leftEar.move(to: NSPoint(x: 206, y: 680))
        leftEar.curve(to: NSPoint(x: 130, y: 900), controlPoint1: NSPoint(x: 131, y: 773), controlPoint2: NSPoint(x: 101, y: 881))
        leftEar.curve(to: NSPoint(x: 360, y: 801), controlPoint1: NSPoint(x: 173, y: 929), controlPoint2: NSPoint(x: 284, y: 884))
        leftEar.close(); leftEar.fill()
        let rightEar = leftEar.copy() as! NSBezierPath
        let mirror = AffineTransform(m11: -1, m12: 0, m21: 0, m22: 1, tX: 1024, tY: 0)
        rightEar.transform(using: mirror); rightEar.fill()
        NSBezierPath(ovalIn: NSRect(x: 130, y: 109, width: 764, height: 728)).fill()
        if template {
            NSGraphicsContext.current?.cgContext.setBlendMode(.destinationOut)
            NSColor.black.setFill()
        } else {
            orange.setFill()
        }
        NSBezierPath(ovalIn: NSRect(x: 261, y: 571, width: 45, height: 45)).fill()
        NSBezierPath(ovalIn: NSRect(x: 718, y: 571, width: 45, height: 45)).fill()
        let letter = NSAttributedString(string: "A", attributes: [.font: NSFont.systemFont(ofSize: 388, weight: .bold), .foregroundColor: template ? NSColor.black : orange])
        letter.draw(at: NSPoint(x: (1024 - letter.size().width) / 2, y: 312))
        let snout = NSBezierPath(ovalIn: NSRect(x: 365, y: 216, width: 294, height: 115))
        if template {
            NSColor.black.setStroke(); snout.lineWidth = 29; snout.stroke()
            NSBezierPath(ovalIn: NSRect(x: 431, y: 253, width: 34, height: 39)).fill()
            NSBezierPath(ovalIn: NSRect(x: 560, y: 253, width: 34, height: 39)).fill()
        } else {
            (orange.blended(withFraction: 0.72, of: face) ?? face).setFill(); snout.fill()
            orange.setFill()
            NSBezierPath(ovalIn: NSRect(x: 431, y: 253, width: 34, height: 39)).fill()
            NSBezierPath(ovalIn: NSRect(x: 560, y: 253, width: 34, height: 39)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
