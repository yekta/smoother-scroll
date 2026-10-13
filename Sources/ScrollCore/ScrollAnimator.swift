import Foundation

/// The values of `CGEventField.scrollWheelEventScrollPhase`.
public enum ScrollPhase: Int64, Sendable {
    case none = 0
    case began = 1
    case changed = 2
    case ended = 4
}

/// The values of `CGEventField.scrollWheelEventMomentumPhase`.
public enum MomentumPhase: Int64, Sendable {
    case none = 0
    case began = 1
    case changed = 2
    case ended = 3
}

/// One scroll event to post, in whole points.
public struct ScrollOutput: Equatable, Sendable {
    public var dx: Int32
    public var dy: Int32
    public var phase: ScrollPhase
    public var momentum: MomentumPhase

    public init(dx: Int32, dy: Int32, phase: ScrollPhase, momentum: MomentumPhase) {
        self.dx = dx
        self.dy = dy
        self.phase = phase
        self.momentum = momentum
    }

    public var moves: Bool { dx != 0 || dy != 0 }
}

/// Turns wheel notches into smooth scrolling, the way SmoothScroll does.
///
/// Each notch is a pulse: its step, eased over the animation time. Pulses add up, so notches that
/// come quickly overlap and the page keeps moving; several in one event make one larger pulse. A notch the other way drops what is left of
/// them. With momentum on, a fast spin also leaves a glide that decays like a trackpad's, which
/// the page keeps to while it is faster than the pulses. With trackpad phases on, the events are a
/// trackpad gesture while notches arrive and its momentum once they stop.
public struct ScrollAnimator: Sendable {
    enum State: Sendable {
        case idle
        case dragging
        case gliding
    }

    struct Pulse: Sendable {
        var dx: Double
        var dy: Double
        var start: Double
    }

    var pulses: [Pulse] = []
    /// What finished pulses moved.
    var finished = (x: 0.0, y: 0.0)
    var position = (x: 0.0, y: 0.0)
    var posted = (x: 0.0, y: 0.0)
    var glide = (x: 0.0, y: 0.0)
    var glideShare = 0.0
    var direction = (x: 0.0, y: 0.0)
    /// When the mouse sent the spin's last few notches, by its own clock.
    var recent: [Double] = []
    var mouseClock = 0.0
    var lastNotch = -Double.infinity
    var state = State.idle
    var releaseDelay = 0.2
    var needsBegin = false
    var needsMomentumBegin = false
    var pending: [ScrollOutput] = []
    public private(set) var time = 0.0

    public init() {}

    public var isIdle: Bool { state == .idle && pending.isEmpty }

    /// A wheel event: `dx` and `dy` are notches, positive up and left like the event's deltas. More
    /// than one is a fast spin's notches sent in one report, spread over the time since the last.
    /// `sinceLastNotch`, when known, is how long after the last event the mouse sent this one.
    public mutating func notch(dx: Double, dy: Double, at now: Double, sinceLastNotch: Double? = nil, tuning: ScrollTuning) {
        guard dx != 0 || dy != 0 else { return }
        if state == .idle {
            time = now
        }
        let at = max(now, time)
        let elapsed = lastNotch.isFinite ? sinceLastNotch ?? (at - lastNotch) : .infinity
        let reversed = (dx != 0 && direction.x != 0 && dx.sign != direction.x.sign)
            || (dy != 0 && direction.y != 0 && dy.sign != direction.y.sign)
        if reversed {
            // A wheel spun fast can tick once the other way: that is the wheel bouncing, not the
            // hand turning back, which takes longer.
            guard elapsed >= ScrollTuning.reversalGuard else { return }
            stopMotion(tuning: tuning)
            recent.removeAll()
        }
        if dx != 0 {
            direction.x = dx
        }
        if dy != 0 {
            direction.y = dy
        }

        if elapsed > ScrollTuning.spinWindow {
            recent.removeAll()
        }
        // The first event's notches have nothing to be spread over, so they say nothing of speed.
        let count = elapsed.isFinite ? max(1, Int(max(abs(dx), abs(dy)).rounded())) : 1
        let gap = elapsed.isFinite ? max(elapsed, 0) / Double(count) : 0
        for _ in 0..<count {
            mouseClock += gap
            recent.append(mouseClock)
        }
        if recent.count > 5 {
            recent.removeFirst(recent.count - 5)
        }
        lastNotch = at

        let rate = Self.rate(of: recent)
        let multiplier = tuning.multiplier(rate: rate)
        pulses.append(Pulse(dx: dx * tuning.stepSize * multiplier, dy: dy * tuning.stepSize * multiplier, start: at))
        glideShare = tuning.glideShare(rate: rate)
        releaseDelay = rate > 0 ? min(max(3 / rate, 0.1), 0.2) : 0.2

        if state == .gliding {
            pending.append(ScrollOutput(dx: 0, dy: 0, phase: .none, momentum: .ended))
        }
        if state != .dragging {
            needsBegin = true
        }
        state = .dragging
    }

    /// Moves the content on to `now` and returns the events that say so.
    public mutating func advance(to now: Double, tuning: ScrollTuning) -> [ScrollOutput] {
        var out = pending
        pending.removeAll()
        guard state != .idle else {
            time = max(time, now)
            return shaped(out, tuning: tuning)
        }

        let elapsed = min(max(now - time, 0), 0.1)
        if elapsed > 0 {
            let steps = max(1, Int((elapsed / 0.002).rounded(.up)))
            let h = elapsed / Double(steps)
            for step in 1...steps {
                move(to: time + h * Double(step), h: h, tuning: tuning)
            }
        }
        time = max(time, now)

        let frame = ScrollOutput(dx: take(\.x), dy: take(\.y), phase: .none, momentum: .none)
        let settled = pulses.isEmpty && glide == (0, 0)
        switch state {
        case .dragging:
            if needsBegin {
                out.append(with(frame, phase: .began))
                needsBegin = false
            } else if frame.moves {
                out.append(with(frame, phase: .changed))
            }
            if time - lastNotch >= releaseDelay {
                out.append(ScrollOutput(dx: 0, dy: 0, phase: .ended, momentum: .none))
                if settled {
                    finish()
                } else {
                    state = .gliding
                    needsMomentumBegin = true
                }
            }
        case .gliding:
            if needsMomentumBegin, frame.moves || settled {
                out.append(with(frame, momentum: .began))
                needsMomentumBegin = false
            } else if frame.moves {
                out.append(with(frame, momentum: .changed))
            }
            if settled {
                out.append(ScrollOutput(dx: 0, dy: 0, phase: .none, momentum: .ended))
                finish()
            }
        case .idle:
            break
        }
        return shaped(out, tuning: tuning)
    }

    /// Stops at once, as a finger on a trackpad stops its momentum, ending what was started.
    public mutating func cancel(tuning: ScrollTuning) -> [ScrollOutput] {
        var out = pending
        pending.removeAll()
        switch state {
        case .dragging where !needsBegin:
            out.append(ScrollOutput(dx: 0, dy: 0, phase: .ended, momentum: .none))
        case .gliding where !needsMomentumBegin:
            out.append(ScrollOutput(dx: 0, dy: 0, phase: .none, momentum: .ended))
        default:
            break
        }
        stopMotion(tuning: tuning)
        recent.removeAll()
        finish()
        return shaped(out, tuning: tuning)
    }

    /// Notches a second over the spin's last few notches; nothing for a notch on its own. Notches
    /// closer than `closestNotches` count as that far apart.
    static func rate(of times: [Double]) -> Double {
        guard times.count >= 2, let first = times.first, let last = times.last else { return 0 }
        let intervals = Double(times.count - 1)
        return intervals / max(last - first, ScrollTuning.closestNotches * intervals)
    }

    private mutating func move(to now: Double, h: Double, tuning: ScrollTuning) {
        let before = base(at: now - h, tuning: tuning)
        let after = base(at: now, tuning: tuning)
        position.x += step(base: after.x - before.x, glide: &glide.x, h: h, tuning: tuning)
        position.y += step(base: after.y - before.y, glide: &glide.y, h: h, tuning: tuning)

        let done = pulses.filter { now - $0.start >= tuning.duration }
        guard !done.isEmpty else { return }
        finished.x += done.reduce(0) { $0 + $1.dx }
        finished.y += done.reduce(0) { $0 + $1.dy }
        pulses.removeAll { now - $0.start >= tuning.duration }
    }

    /// Where the pulses have the page at `time`.
    private func base(at time: Double, tuning: ScrollTuning) -> (x: Double, y: Double) {
        pulses.reduce(finished) { sum, pulse in
            let eased = tuning.ease((time - pulse.start) / tuning.duration)
            return (sum.x + pulse.dx * eased, sum.y + pulse.dy * eased)
        }
    }

    /// One axis's move over `h`: the pulses', or the glide's while it is faster.
    private func step(base: Double, glide: inout Double, h: Double, tuning: ScrollTuning) -> Double {
        guard tuning.momentumEnabled else { return base }
        let speed = base / h
        if glide != 0 {
            let decay = tuning.friction * tuning.glideTime
            let magnitude = max(0, (abs(glide) + decay) * exp(-h / tuning.glideTime) - decay)
            glide = magnitude < 1 ? 0 : magnitude * (glide > 0 ? 1 : -1)
        }
        if abs(glideShare * speed) > abs(glide), glide == 0 || glide.sign == speed.sign {
            glide = glideShare * speed
        }
        guard abs(glide) > abs(speed) else { return base }
        return glide * h
    }

    /// Drops what is left of the motion where it is.
    private mutating func stopMotion(tuning: ScrollTuning) {
        finished = base(at: time, tuning: tuning)
        pulses.removeAll()
        glide = (0, 0)
        lastNotch = -.infinity
    }

    private mutating func take(_ axis: WritableKeyPath<(x: Double, y: Double), Double>) -> Int32 {
        let rounded = position[keyPath: axis].rounded()
        let delta = rounded - posted[keyPath: axis]
        posted[keyPath: axis] = rounded
        return Int32(clamping: Int(delta))
    }

    private mutating func finish() {
        state = .idle
        needsBegin = false
        needsMomentumBegin = false
        pulses.removeAll()
        finished = (0, 0)
        position = (0, 0)
        posted = (0, 0)
        glide = (0, 0)
    }

    private func with(_ frame: ScrollOutput, phase: ScrollPhase = .none, momentum: MomentumPhase = .none) -> ScrollOutput {
        ScrollOutput(dx: frame.dx, dy: frame.dy, phase: phase, momentum: momentum)
    }

    /// Without trackpad phases, only the moves are sent, as plain continuous scrolling.
    private func shaped(_ outputs: [ScrollOutput], tuning: ScrollTuning) -> [ScrollOutput] {
        guard !tuning.phases else { return outputs }
        return outputs.filter(\.moves).map { ScrollOutput(dx: $0.dx, dy: $0.dy, phase: .none, momentum: .none) }
    }
}
