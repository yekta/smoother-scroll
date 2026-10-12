import AppKit

/// Lucide's `mouse` icon (ISC licensed), drawn as a template image for the menu bar.
enum LucideMouse {
    static func image(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            let scale = size / 24
            let transform = NSAffineTransform()
            transform.scale(by: scale)
            transform.concat()

            NSColor.black.setStroke()
            let body = NSBezierPath(roundedRect: NSRect(x: 5, y: 2, width: 14, height: 20), xRadius: 7, yRadius: 7)
            let wheel = NSBezierPath()
            wheel.move(to: NSPoint(x: 12, y: 6))
            wheel.line(to: NSPoint(x: 12, y: 10))
            for path in [body, wheel] {
                path.lineWidth = 2
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Smoother Scroll"
        return image
    }
}
