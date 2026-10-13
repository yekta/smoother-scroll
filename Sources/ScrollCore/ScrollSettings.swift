import Foundation

public struct ExcludedApp: Codable, Hashable, Identifiable, Sendable {
    public var bundleID: String
    public var name: String
    public var path: String?

    public var id: String { bundleID }

    public init(bundleID: String, name: String, path: String?) {
        self.bundleID = bundleID
        self.name = name
        self.path = path
    }
}

/// Everything the user can tune; the defaults start from a SmoothScroll setup. A setting missing
/// from what was saved takes its default, so adding one never resets the others.
public struct ScrollSettings: Codable, Equatable, Sendable {
    public var enabled = true
    /// Points one notch of the wheel scrolls.
    public var stepSize: Double = 150
    /// Milliseconds one notch's animation lasts.
    public var animationTime: Double = 350
    /// How much a fast spin speeds each notch up: 0 is off, 1 the default, 2 twice as much.
    public var acceleration: Double = 1
    /// The most a notch can be multiplied by.
    public var accelerationMax: Double = 20
    /// A notch starts slowly instead of at full speed, on Apple's ease in.
    public var easeIn = true
    /// A notch slows down to a stop instead of stopping at full speed, on Apple's ease out.
    public var easeOut = true
    /// With both, how much longer a notch eases out than in; 1 is Apple's ease in and out.
    public var tailToHeadRatio: Double = 1
    /// 0 is off; how long a fast spin glides on after the wheel stops, like a trackpad flick.
    public var momentum: Double = 0
    /// Sends the scroll phases a trackpad sends, so views rubber-band at their edges.
    public var trackpadPhases = false
    public var smoothHorizontal = true
    public var reverseDirection = false
    public var excludedApps: [ExcludedApp] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ScrollSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        enabled = value(.enabled, defaults.enabled)
        stepSize = value(.stepSize, defaults.stepSize)
        animationTime = value(.animationTime, defaults.animationTime)
        acceleration = value(.acceleration, defaults.acceleration)
        accelerationMax = value(.accelerationMax, defaults.accelerationMax)
        easeIn = value(.easeIn, defaults.easeIn)
        easeOut = value(.easeOut, defaults.easeOut)
        tailToHeadRatio = value(.tailToHeadRatio, defaults.tailToHeadRatio)
        momentum = value(.momentum, defaults.momentum)
        trackpadPhases = value(.trackpadPhases, defaults.trackpadPhases)
        smoothHorizontal = value(.smoothHorizontal, defaults.smoothHorizontal)
        reverseDirection = value(.reverseDirection, defaults.reverseDirection)
        excludedApps = value(.excludedApps, defaults.excludedApps)
    }

    public static let ranges = (
        stepSize: 10.0...1000.0,
        animationTime: 50.0...1500.0,
        acceleration: 0.0...2.0,
        accelerationMax: 1.0...50.0,
        tailToHeadRatio: 0.5...6.0,
        momentum: 0.0...1.0
    )
}
