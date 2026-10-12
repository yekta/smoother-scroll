import Foundation

/// The settings turned into the numbers the animator runs on. Times are in seconds.
public struct ScrollTuning: Equatable, Sendable {
    /// A notch eases in over `head` and out over `tail`: two lags one after the other.
    public var head: Double
    public var tail: Double
    public var stepSize: Double
    public var acceleration: Double
    public var maxAcceleration: Double
    /// How fast a glide slows: its speed decays over `glideTime` and loses `friction` points per
    /// second, every second, so it stops instead of crawling.
    public var glideTime: Double
    public var friction: Double
    public var momentumEnabled: Bool
    public var phases: Bool

    /// Notches further apart than this are not one spin.
    public static let spinWindow = 0.4
    /// Notches a second where a spin starts to glide on, and where it glides fully.
    public static let glideRates = 4.0...12.0
    /// Notches a second above which acceleration starts.
    public static let accelerationStart = 15.0

    public init(_ settings: ScrollSettings) {
        let duration = max(settings.animationTime, 1) / 1000
        let ratio = max(settings.tailToHeadRatio, 1)
        head = duration / Self.settleTime(ratio: ratio)
        tail = head * ratio
        stepSize = settings.stepSize
        acceleration = max(settings.acceleration, 0)
        maxAcceleration = max(settings.maxAcceleration, 1)
        momentumEnabled = settings.momentum > 0
        glideTime = 0.15 + 0.6 * min(max(settings.momentum, 0), 1)
        friction = 250
        phases = settings.trackpadPhases
    }

    public func multiplier(rate: Double) -> Double {
        let over = max(0, rate - Self.accelerationStart) / 30
        return min(maxAcceleration, 1 + acceleration * over)
    }

    /// 0 for notches one by one, 1 for a fast spin.
    public func glideShare(rate: Double) -> Double {
        guard momentumEnabled else { return 0 }
        let range = Self.glideRates
        let x = min(max((rate - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
        return x * x * (3 - 2 * x)
    }

    /// How far a glide starting at `speed` goes before it stops.
    public func glideDistance(speed: Double) -> Double {
        let decay = friction * glideTime
        return glideTime * (speed - decay * log(1 + speed / decay))
    }

    /// When a notch of two lags, the first taking 1 and the second `ratio`, is 98% of the way.
    static func settleTime(ratio: Double) -> Double {
        func progress(_ t: Double) -> Double {
            if abs(ratio - 1) < 0.001 { return 1 - (1 + t) * exp(-t) }
            return 1 - (ratio * exp(-t / ratio) - exp(-t)) / (ratio - 1)
        }
        var low = 0.0
        var high = 100 * ratio
        for _ in 0..<60 {
            let mid = (low + high) / 2
            if progress(mid) < 0.98 { low = mid } else { high = mid }
        }
        return high
    }
}
