import CoreGraphics
import Foundation

/// What each wheel event says, written to ~/Library/Logs/Smoother Scroll/wheel.log when turned on
/// with `defaults write com.yekta.SmootherScroll logWheelEvents -bool true`, to see how a mouse
/// sends its notches.
final class WheelLog {
    private let file: FileHandle?

    init() {
        guard UserDefaults.standard.bool(forKey: "logWheelEvents") else {
            file = nil
            return
        }
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Smoother Scroll")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("wheel.log")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        file = try? FileHandle(forWritingTo: url)
        _ = try? file?.seekToEnd()
    }

    func write(_ event: CGEvent, notch: (dx: Double, dy: Double)?) {
        guard let file else { return }
        let fields: [(String, CGEventField)] = [
            ("line", .scrollWheelEventDeltaAxis1), ("point", .scrollWheelEventPointDeltaAxis1),
            ("lineX", .scrollWheelEventDeltaAxis2), ("pointX", .scrollWheelEventPointDeltaAxis2),
            ("continuous", .scrollWheelEventIsContinuous), ("phase", .scrollWheelEventScrollPhase),
            ("momentum", .scrollWheelEventMomentumPhase),
        ]
        var line = String(format: "%.4f", Double(event.timestamp) / 1e9)
        line += String(format: " fixed=%.3f fixedX=%.3f", event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
                       event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2))
        for (name, field) in fields {
            line += " \(name)=\(event.getIntegerValueField(field))"
        }
        line += " flags=\(String(event.flags.rawValue, radix: 16))"
        line += notch.map { " notch=\($0.dx),\($0.dy)" } ?? " passed"
        file.write(Data((line + "\n").utf8))
    }
}
