import AppKit

/// Which app a scroll at a point goes to: the owner of the frontmost window under it.
enum AppLookup {
    static func bundleID(at point: CGPoint) -> String? {
        guard let pid = owner(at: point) else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    private static func owner(at point: CGPoint) -> pid_t? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        for window in windows {
            // Above the floating levels are the Dock's, Notification Center's and the cursor's
            // windows, which cover the screen but never scroll.
            guard let layer = window[kCGWindowLayer as String] as? Int, (0..<20).contains(layer) else { continue }
            guard let alpha = window[kCGWindowAlpha as String] as? Double, alpha > 0 else { continue }
            guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.contains(point) else { continue }
            return window[kCGWindowOwnerPID as String] as? pid_t
        }
        return nil
    }
}
