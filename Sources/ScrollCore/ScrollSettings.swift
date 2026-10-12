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

/// Everything the user can tune. A setting missing from what was saved takes its default, so
/// adding one never resets the others.
public struct ScrollSettings: Codable, Equatable, Sendable {
    public var enabled = true
    /// Points one notch of the wheel scrolls.
    public var stepSize: Double = 250
    /// Milliseconds one notch takes to settle.
    public var animationTime: Double = 350
    /// How much longer the easing out of a notch is than the easing in.
    public var tailToHeadRatio: Double = 2
    /// 0 is off; 1 roughly doubles a notch at 45 notches a second.
    public var acceleration: Double = 1
    public var maxAcceleration: Double = 10
    /// 0 is off; how long a fast spin glides on once the wheel stops, like a trackpad flick.
    public var momentum: Double = 0.5
    /// Sends the scroll phases a trackpad sends, so views rubber-band at their edges.
    public var trackpadPhases = true
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
        tailToHeadRatio = value(.tailToHeadRatio, defaults.tailToHeadRatio)
        acceleration = value(.acceleration, defaults.acceleration)
        maxAcceleration = value(.maxAcceleration, defaults.maxAcceleration)
        momentum = value(.momentum, defaults.momentum)
        trackpadPhases = value(.trackpadPhases, defaults.trackpadPhases)
        smoothHorizontal = value(.smoothHorizontal, defaults.smoothHorizontal)
        reverseDirection = value(.reverseDirection, defaults.reverseDirection)
        excludedApps = value(.excludedApps, defaults.excludedApps)
    }

    public static let ranges = (
        stepSize: 20.0...600.0,
        animationTime: 80.0...1000.0,
        tailToHeadRatio: 1.0...6.0,
        acceleration: 0.0...3.0,
        maxAcceleration: 1.0...250.0,
        momentum: 0.0...1.0
    )
}
