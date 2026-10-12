import AppKit
import SwiftUI

/// The settings window: the desktop shows through it, blurred, under glass cards. While it is
/// open the app shows in the Dock and the app switcher, so it can't get lost behind other windows.
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
        let size = NSSize(width: 500, height: 760)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Smoother Scroll"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear

        window.contentView = NSHostingView(rootView: SettingsView(model: model))

        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("Settings")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
