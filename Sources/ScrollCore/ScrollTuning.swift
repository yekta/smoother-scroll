import Foundation

/// The settings turned into the numbers the animator runs on. Times are in seconds.
public struct ScrollTuning: Equatable, Sendable {
    public var duration: Double
    public var stepSize: Double
    public var acceleration: Double
    public var accelerationMax: Double
    public var easeIn: Bool
    public var easeOut: Bool
    /// With both easings, the share of a notch's time and distance spent speeding up; the rest is
    /// spent slowing down. A half is Apple's ease in and out as it is.
    public var head: Double
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
        head = 1 / (1 + max(settings.tailToHeadRatio, 0.1))
        momentumEnabled = settings.momentum > 0
        glideTime = 0.15 + 0.6 * min(max(settings.momentum, 0), 1)
        friction = 250
        phases = settings.trackpadPhases
    }

    /// How far into its step a notch is, `progress` of the way through its animation: Apple's
    /// ease in, ease out, or ease in and out.
    public func ease(_ progress: Double) -> Double {
        let progress = min(max(progress, 0), 1)
        switch (easeIn, easeOut) {
        case (true, true): return easeInEaseOut(progress)
        case (false, true): return CubicBezier.easeOut.value(at: progress)
        case (true, false): return CubicBezier.easeIn.value(at: progress)
        case (false, false): return progress
        }
    }

    /// Apple's ease in and out, its halves stretched so that speeding up takes `head` of the notch.
    /// The halves meet at the same speed, as each covers as much of the distance as of the time.
    private func easeInEaseOut(_ progress: Double) -> Double {
        let curve = CubicBezier.easeInEaseOut
        guard progress >= head else {
            return 2 * head * curve.value(at: progress / head / 2)
        }
        let tail = (progress - head) / (1 - head)
        return head + (1 - head) * 2 * (curve.value(at: 0.5 + tail / 2) - 0.5)
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
