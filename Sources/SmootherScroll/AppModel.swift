import AppKit
import ApplicationServices
import Observation
import ScrollCore
import ServiceManagement

@MainActor
@Observable
final class AppModel {
    private enum Key {
        /// Settings saved before SmoothScroll's settings became ours; only what still means the
        /// same is taken from them.
        static let oldSettings = "settings"
        static let settings = "smoothScrollSettings"
        static let hasLaunched = "hasLaunched"
    }

    var settings: ScrollSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
            engine.update(settings)
            onChange?()
        }
    }

    private(set) var hasAccess = AXIsProcessTrusted()
    private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var loginItemError: String?

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored let isFirstLaunch: Bool
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored let updater = Updater()
    @ObservationIgnored private let engine = ScrollEngine()
    @ObservationIgnored private var accessTimer: Timer?

    init() {
        settings = Self.savedSettings(in: defaults)
        isFirstLaunch = !defaults.bool(forKey: Key.hasLaunched)
        defaults.set(true, forKey: Key.hasLaunched)
        engine.update(settings)
    }

    /// Starts the engine as soon as the app has Accessibility access, and keeps watching it.
    func start() {
        if isFirstLaunch {
            setLaunchAtLogin(true)
        }
        refreshAccess()
        accessTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccess() }
        }
    }

    private func refreshAccess() {
        let trusted = AXIsProcessTrusted()
        if trusted, !engine.isRunning {
            _ = engine.start()
        }
        guard trusted != hasAccess else { return }
        hasAccess = trusted
        onChange?()
    }

    func requestAccess() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Apps

    func isExcluded(_ bundleID: String) -> Bool {
        settings.excludedApps.contains { $0.bundleID == bundleID }
    }

    func exclude(_ app: ExcludedApp) {
        guard !isExcluded(app.bundleID) else { return }
        settings.excludedApps.append(app)
        settings.excludedApps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func include(_ bundleID: String) {
        settings.excludedApps.removeAll { $0.bundleID == bundleID }
    }

    func restoreDefaults() {
        var restored = ScrollSettings()
        restored.enabled = settings.enabled
        restored.excludedApps = settings.excludedApps
        settings = restored
    }

    private static func savedSettings(in defaults: UserDefaults) -> ScrollSettings {
        let decode = { (key: String) in
            defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(ScrollSettings.self, from: $0) }
        }
        if let saved = decode(Key.settings) {
            return saved
        }
        var settings = ScrollSettings()
        if let old = decode(Key.oldSettings) {
            settings.enabled = old.enabled
            settings.smoothHorizontal = old.smoothHorizontal
            settings.reverseDirection = old.reverseDirection
            settings.excludedApps = old.excludedApps
        }
        return settings
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Key.settings)
    }
}

extension ExcludedApp {
    init?(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return nil }
        self.init(bundleID: bundleID, name: app.localizedName ?? bundleID, path: app.bundleURL?.path)
    }

    init?(url: URL) {
        guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        self.init(bundleID: bundleID, name: name, path: url.path)
    }

    var icon: NSImage {
        let url = path.map { URL(fileURLWithPath: $0) }.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        guard let url else { return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage() }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
