import AppKit
import ScrollCore

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let actions: AppActions
    private var item: NSStatusItem?

    init(model: AppModel, actions: AppActions) {
        self.model = model
        self.actions = actions
    }

    func update() {
        guard model.showsMenuBarIcon else {
            if let item {
                NSStatusBar.system.removeStatusItem(item)
            }
            item = nil
            return
        }
        let item = item ?? makeItem()
        self.item = item
        item.button?.appearsDisabled = !model.settings.enabled || !model.hasAccess
    }

    private func makeItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = LucideMouse.image()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !model.hasAccess {
            let access = NSMenuItem(title: "Allow Accessibility Access…", action: #selector(requestAccess), keyEquivalent: "")
            access.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            access.target = self
            menu.addItem(access)
            menu.addItem(.separator())
        }

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
        menu.addItem(actionItem("Settings…", #selector(AppActions.showSettings), key: ","))
        menu.addItem(actionItem("Check for Updates…", #selector(AppActions.checkForUpdates)))
        menu.addItem(actionItem("About Smoother Scroll", #selector(AppActions.showAbout)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Smoother Scroll", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func actionItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = actions
        return item
    }

    private func frontmostApp() -> ExcludedApp? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        return ExcludedApp(app)
    }

    @objc private func requestAccess() {
        model.requestAccess()
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
