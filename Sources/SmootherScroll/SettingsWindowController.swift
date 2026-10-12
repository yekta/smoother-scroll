import AppKit
import SwiftUI

/// The settings window, of tinted glass: black in dark mode, white in light. While it is open the
/// app shows in the Dock and the app switcher, so it can't get lost behind other windows.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Smoother Scroll"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = glass(around: NSHostingView(rootView: SettingsView(model: model)))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("Settings")
        return window
    }

    /// A heavy blur of the desktop under tinted glass, so the window reads as frosted, not clear.
    private func glass(around content: NSView) -> NSView {
        let blur = NSVisualEffectView()
        blur.material = .underWindowBackground
        blur.blendingMode = .behindWindow
        blur.state = .active
        guard #available(macOS 26.0, *) else {
            fill(blur, with: content)
            return blur
        }
        let glass = NSGlassEffectView()
        glass.cornerRadius = 16
        glass.tintColor = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? NSColor.black.withAlphaComponent(0.55) : NSColor.white.withAlphaComponent(0.3)
        }
        glass.contentView = content
        fill(blur, with: glass)
        return blur
    }

    private func fill(_ container: NSView, with view: NSView) {
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
