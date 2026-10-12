import AppKit

/// Asks GitHub for the latest release and installs it when it is newer than this one.
///
/// The app downloads the update itself: a browser's download would be quarantined, and as the
/// app isn't notarized, Gatekeeper would block it.
@MainActor
enum UpdateChecker {
    static let repository = URL(string: "https://github.com/yekta/smoother-scroll")!
    private static let latest = URL(string: "https://api.github.com/repos/yekta/smoother-scroll/releases/latest")!
    private static let assetName = "SmootherScroll.zip"

    private struct Release: Decodable {
        let tagName: String
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
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
            guard version.compare(currentVersion, options: .numeric) == .orderedDescending,
                  let asset = release.assets.first(where: { $0.name == assetName }) else {
                alert.messageText = "Smoother Scroll is up to date"
                alert.informativeText = "Version \(currentVersion) is the latest."
                present(alert)
                return
            }
            alert.messageText = "Smoother Scroll \(version) is available"
            alert.informativeText = "You have version \(currentVersion). It restarts once installed; macOS then asks for Accessibility access again."
            alert.addButton(withTitle: "Install and Restart")
            alert.addButton(withTitle: "Later")
            guard present(alert) == .alertFirstButtonReturn else { return }
            try await install(from: asset.browserDownloadURL)
        } catch {
            let failure = NSAlert()
            failure.messageText = "Couldn't update Smoother Scroll"
            failure.informativeText = error.localizedDescription
            present(failure)
        }
    }

    /// Unzips the update next to the download, then hands over to a shell that waits for this app
    /// to quit, puts the new one in its place and opens it.
    private static func install(from url: URL) async throws {
        let (download, _) = try await URLSession.shared.download(from: url)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", download.path, folder.path])
        let update = folder.appendingPathComponent("Smoother Scroll.app")
        guard FileManager.default.fileExists(atPath: update.path) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let swap = """
            while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
            rm -rf "$2" && mv "$3" "$2" && xattr -dr com.apple.quarantine "$2"
            open "$2"
            """
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", swap, "sh", "\(ProcessInfo.processInfo.processIdentifier)",
                           Bundle.main.bundleURL.path, update.path]
        try shell.run()
        NSApp.terminate(nil)
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
    }

    @discardableResult
    private static func present(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate()
        return alert.runModal()
    }
}
