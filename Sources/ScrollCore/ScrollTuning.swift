import Foundation

/// The settings turned into the numbers the animator runs on. Times are in seconds.
public struct ScrollTuning: Equatable, Sendable {
    public var duration: Double
    public var stepSize: Double
    public var acceleration: Double
    public var accelerationMax: Double
    public var easeIn: Bool
    public var easeOut: Bool
    /// SmoothScroll's pulse, for easing in and out: the first 1/`pulseScale` of a notch eases in,
    /// the rest eases out.
    public var pulseScale: Double
    public var pulseNormalize: Double
    /// How fast a glide slows: its speed decays over `glideTime` and loses `friction` points per
    /// second, every second, so it stops instead of crawling.
    public var glideTime: Double
    public var friction: Double
    public var momentumEnabled: Bool
    public var phases: Bool

    /// Notches further apart than this are not one spin.
    public static let spinWindow = 0.4
    /// The closest two notches count as: a mouse can send two in one report.
    public static let closestNotches = 0.012
    /// A notch the other way sooner than this after the last one is the wheel bouncing.
    public static let reversalGuard = 0.12
    /// Notches a second where a spin starts to glide on, and where it glides fully.
    public static let glideRates = 4.0...12.0

    public init(_ settings: ScrollSettings) {
        duration = max(settings.animationTime, 1) / 1000
        stepSize = settings.stepSize
        acceleration = max(settings.acceleration, 0)
        accelerationMax = max(settings.accelerationMax, 1)
        easeIn = settings.easeIn
        easeOut = settings.easeOut
        pulseScale = 1 + max(settings.tailToHeadRatio, 0)
        pulseNormalize = 1
        momentumEnabled = settings.momentum > 0
        glideTime = 0.15 + 0.6 * min(max(settings.momentum, 0), 1)
        friction = 250
        phases = settings.trackpadPhases
        pulseNormalize = 1 / pulse(1)
    }

    /// How steeply a notch eases out on its own: it ends at e⁻⁴, 2%, of its starting speed.
    static let easeOutSteepness = 4.0

    /// How far into its step a notch is, `progress` of the way through its animation.
    public func ease(_ progress: Double) -> Double {
        let progress = min(max(progress, 0), 1)
        guard progress < 1 else { return 1 }
        switch (easeIn, easeOut) {
        case (true, true): return pulse(progress) * pulseNormalize
        case (false, true): return Self.decelerate(progress)
        case (true, false): return 1 - Self.decelerate(1 - progress)
        case (false, false): return progress
        }
    }

    /// Starts at full speed and slows exponentially to nearly nothing.
    private static func decelerate(_ progress: Double) -> Double {
        let k = easeOutSteepness
        return (1 - exp(-k * progress)) / (1 - exp(-k))
    }

    /// Michael Herf's viscous fluid pulse, as SmoothScroll uses it.
    private func pulse(_ progress: Double) -> Double {
        let x = progress * pulseScale
        guard x >= 1 else { return x - (1 - exp(-x)) }
        let start = exp(-1.0)
        return start + (1 - exp(-(x - 1))) * (1 - start)
    }

    /// Up to this many notches a second, each moves exactly its step.
    public static let accelerationStart = 3.0

    /// How much a notch is multiplied by when the wheel spins at `rate` notches a second: not at all
    /// up to 3, then more and more the faster it spins. At the default strength 10 a second
    /// makes 1.6×, 20 makes 3.2× and 40 makes 8×.
    public func multiplier(rate: Double) -> Double {
        let over = max(0, rate - Self.accelerationStart)
        return min(accelerationMax, 1 + acceleration * 0.032 * pow(over, 1.5))
    }

    /// 0 for notches one by one, 1 for a fast spin.
    public func glideShare(rate: Double) -> Double {
        guard momentumEnabled else { return 0 }
        let range = Self.glideRates
        let x = min(max((rate - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
        return x * x * (3 - 2 * x)
    }
}
