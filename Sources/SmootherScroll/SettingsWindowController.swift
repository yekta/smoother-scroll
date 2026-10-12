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

    private func glass(around content: NSView) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 16
            glass.tintColor = NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return isDark ? NSColor.black.withAlphaComponent(0.4) : NSColor.white.withAlphaComponent(0.6)
            }
            glass.contentView = content
            return glass
        }
        let material = NSVisualEffectView()
        material.material = .windowBackground
        material.blendingMode = .behindWindow
        material.state = .active
        content.frame = material.bounds
        content.autoresizingMask = [.width, .height]
        material.addSubview(content)
        return material
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
