import AppKit

/// Asks GitHub for the latest release and offers it when it is newer than this one.
@MainActor
enum UpdateChecker {
    static let repository = URL(string: "https://github.com/yekta/smoother-scroll")!
    private static let latest = URL(string: "https://api.github.com/repos/yekta/smoother-scroll/releases/latest")!

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func check() async {
        let alert = NSAlert()
        do {
            var request = URLRequest(url: latest)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            let release = try JSONDecoder().decode(Release.self, from: data)
            let version = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            guard version.compare(currentVersion, options: .numeric) == .orderedDescending else {
                alert.messageText = "Smoother Scroll is up to date"
                alert.informativeText = "Version \(currentVersion) is the latest."
                present(alert)
                return
            }
            alert.messageText = "Smoother Scroll \(version) is available"
            alert.informativeText = "You have version \(currentVersion)."
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Later")
            if present(alert) == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.htmlURL)
            }
        } catch {
            alert.messageText = "Couldn't check for updates"
            alert.informativeText = error.localizedDescription
            present(alert)
        }
    }

    @discardableResult
    private static func present(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate()
        return alert.runModal()
    }
}
