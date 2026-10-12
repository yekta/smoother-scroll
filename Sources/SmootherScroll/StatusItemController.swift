import AppKit
import ScrollCore
import SwiftUI

/// The menu bar item. A click drops the settings panel down from it; a right click shows a short
/// menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate, NSPopoverDelegate {
    private let model: AppModel
    private let actions: AppActions
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel = NSPopover()
    private let menu = NSMenu()

    init(model: AppModel, actions: AppActions) {
        self.model = model
        self.actions = actions
        super.init()

        panel.behavior = .transient
        panel.animates = true
        panel.delegate = self
        let content = NSHostingController(rootView: SettingsView(model: model))
        content.sizingOptions = []
        panel.contentViewController = content
        panel.contentSize = SettingsView.size

        menu.autoenablesItems = false
        menu.delegate = self

        guard let button = item.button else { return }
        button.image = LucideMouse.image()
        button.target = self
        button.action = #selector(clicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    func update() {
        item.button?.appearsDisabled = !model.settings.enabled || !model.hasAccess
    }

    func showPanel() {
        guard let button = item.button, !panel.isShown else { return }
        NSApp.activate()
        panel.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        panel.contentViewController?.view.window?.makeFirstResponder(nil)
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            panel.performClose(nil)
            item.menu = menu
            sender.performClick(nil)
            item.menu = nil
            return
        }
        if panel.isShown {
            panel.performClose(nil)
        } else {
            showPanel()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let update = model.updater.available {
            let title = model.updater.isInstalling ? "Installing \(update.version)…" : "Install \(update.version) and Restart"
            let install = actionItem(title, #selector(AppActions.installUpdate))
            install.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
            install.isEnabled = !model.updater.isInstalling
            menu.addItem(install)
            menu.addItem(.separator())
        }

        let enabled = NSMenuItem(title: "Smooth Scrolling", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.state = model.settings.enabled ? .on : .off
        enabled.target = self
        menu.addItem(enabled)

        if let app = frontmostApp() {
            let excluded = NSMenuItem(title: "Disable in \(app.name)", action: #selector(toggleFrontmostApp(_:)), keyEquivalent: "")
            excluded.state = model.isExcluded(app.bundleID) ? .on : .off
            excluded.representedObject = app
            excluded.target = self
            menu.addItem(excluded)
        }

        menu.addItem(.separator())
        menu.addItem(actionItem("Settings…", #selector(AppActions.showSettings)))
        menu.addItem(actionItem("About Smoother Scroll", #selector(AppActions.showAbout)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Smoother Scroll", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = actions
        return item
    }

    private func frontmostApp() -> ExcludedApp? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        return ExcludedApp(app)
    }

    @objc private func toggleEnabled() {
        model.settings.enabled.toggle()
    }

    @objc private func toggleFrontmostApp(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? ExcludedApp else { return }
        if model.isExcluded(app.bundleID) {
            model.include(app.bundleID)
        } else {
            model.exclude(app)
        }
    }
}
