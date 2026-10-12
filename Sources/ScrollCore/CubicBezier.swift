import Foundation

/// A timing curve from (0, 0) to (1, 1), as Core Animation's `CAMediaTimingFunction` defines one.
public struct CubicBezier: Equatable, Sendable {
    public var x1: Double
    public var y1: Double
    public var x2: Double
    public var y2: Double

    public static let easeIn = CubicBezier(x1: 0.42, y1: 0, x2: 1, y2: 1)
    public static let easeOut = CubicBezier(x1: 0, y1: 0, x2: 0.58, y2: 1)
    public static let easeInEaseOut = CubicBezier(x1: 0.42, y1: 0, x2: 0.58, y2: 1)

    /// The curve's value `x` of the way through.
    public func value(at x: Double) -> Double {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        return coordinate(at: parameter(for: x), y1, y2)
    }

    private func coordinate(at t: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
    }

    private func slope(at t: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * p1 + 6 * u * t * (p2 - p1) + 3 * t * t * (1 - p2)
    }

    /// The curve's parameter where its x is `x`: Newton's method, and halving where that stalls.
    private func parameter(for x: Double) -> Double {
        var t = x
        for _ in 0..<8 {
            let error = coordinate(at: t, x1, x2) - x
            guard abs(error) > 1e-7 else { return t }
            let d = slope(at: t, x1, x2)
            guard abs(d) > 1e-6 else { break }
            t -= error / d
        }
        var low = 0.0
        var high = 1.0
        t = x
        for _ in 0..<40 {
            let value = coordinate(at: t, x1, x2)
            guard abs(value - x) > 1e-7 else { return t }
            if value < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return t
    }
}
