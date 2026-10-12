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

/// Turns wheel notches into the smooth motion a trackpad would make.
///
/// Each notch moves a target; the content follows it through two lags, which ease the notch in
/// and out and land exactly on it. A fast spin also leaves a glide behind: a speed that decays
/// like a trackpad's momentum, which the content keeps to when it is faster than the notches.
/// While notches arrive the events are a trackpad gesture; once they stop, its momentum.
public struct ScrollAnimator: Sendable {
    enum State: Sendable {
        case idle
        case dragging
        case gliding
    }

    var x = AxisMotion()
    var y = AxisMotion()
    var state = State.idle
    var lastNotch = -Double.infinity
    var releaseDelay = 0.2
    var needsBegin = false
    var needsMomentumBegin = false
    var pending: [ScrollOutput] = []
    public private(set) var time = 0.0

    public init() {}

    public var isIdle: Bool { state == .idle && pending.isEmpty }

    /// A wheel event: `dx` and `dy` are notches, positive up and left like the event's deltas.
    public mutating func notch(dx: Double, dy: Double, at now: Double, tuning: ScrollTuning) {
        guard dx != 0 || dy != 0 else { return }
        if state == .idle {
            time = now
        }
        let at = max(now, time)
        if state == .gliding {
            pending.append(ScrollOutput(dx: 0, dy: 0, phase: .none, momentum: .ended))
        }
        if state != .dragging {
            needsBegin = true
        }
        state = .dragging
        if dx != 0 {
            x.notch(dx, at: at, tuning: tuning)
        }
        if dy != 0 {
            y.notch(dy, at: at, tuning: tuning)
        }
        let rate = max(x.rate, y.rate)
        releaseDelay = rate > 0 ? min(max(3 / rate, 0.1), 0.2) : 0.2
        lastNotch = at
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
            let steps = max(1, Int((elapsed / 0.001).rounded(.up)))
            let h = elapsed / Double(steps)
            for _ in 0..<steps {
                x.step(h, tuning: tuning)
                y.step(h, tuning: tuning)
            }
        }
        time = max(time, now)

        let frame = ScrollOutput(dx: x.take(), dy: y.take(), phase: .none, momentum: .none)
        let settled = x.isSettled && y.isSettled
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
        x.stop()
        y.stop()
        finish()
        return shaped(out, tuning: tuning)
    }

    private mutating func finish() {
        state = .idle
        needsBegin = false
        needsMomentumBegin = false
        x.rebase()
        y.rebase()
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

struct AxisMotion: Sendable {
    var target = 0.0
    var head = 0.0
    var base = 0.0
    var position = 0.0
    var posted = 0.0
    var glideSpeed = 0.0
    var glideShare = 0.0
    var direction = 0.0
    /// The last few notches of this spin. Events can arrive bunched, so its speed is measured
    /// over several of them, never between two.
    var recent: [(time: Double, amount: Double)] = []
    /// Notches a second.
    var rate = 0.0

    var isSettled: Bool {
        abs(target - base) < 0.5 && abs(target - head) < 0.5 && glideSpeed == 0
    }

    mutating func notch(_ amount: Double, at time: Double, tuning: ScrollTuning) {
        let sign: Double = amount > 0 ? 1 : -1
        if direction != 0, sign != direction {
            stop()
        }
        if let last = recent.last, time - last.time > ScrollTuning.spinWindow {
            recent.removeAll()
        }
        recent.append((time, abs(amount)))
        if recent.count > 6 {
            recent.removeFirst()
        }
        rate = Self.rate(of: recent)
        direction = sign
        glideShare = tuning.glideShare(rate: rate)
        target += amount * tuning.stepSize * tuning.multiplier(rate: rate)
    }

    /// Drops what is left of the motion where it is.
    mutating func stop() {
        target = base
        head = base
        glideSpeed = 0
        rate = 0
        recent.removeAll()
    }

    /// Notches a second over a spin's last notches; nothing until there are three.
    static func rate(of notches: [(time: Double, amount: Double)]) -> Double {
        guard notches.count >= 3, let first = notches.first, let last = notches.last else { return 0 }
        let amount = notches.dropFirst().reduce(0) { $0 + $1.amount }
        let span = max(last.time - first.time, 0.005 * Double(notches.count - 1))
        return amount / span
    }

    mutating func step(_ h: Double, tuning: ScrollTuning) {
        let before = base
        head += (target - head) * (1 - exp(-h / tuning.head))
        base += (head - base) * (1 - exp(-h / tuning.tail))
        let baseStep = base - before
        let baseSpeed = baseStep * direction / h

        if glideSpeed > 0 {
            let decay = tuning.friction * tuning.glideTime
            glideSpeed = max(0, (glideSpeed + decay) * exp(-h / tuning.glideTime) - decay)
        }
        glideSpeed = max(glideSpeed, glideShare * baseSpeed)
        position += glideSpeed > baseSpeed ? glideSpeed * h * direction : baseStep

        if abs(target - base) < 0.5, abs(target - head) < 0.5, glideSpeed < 1 {
            position += target - base
            base = target
            head = target
            glideSpeed = 0
        }
    }

    /// The whole points moved since the last call.
    mutating func take() -> Int32 {
        let rounded = position.rounded()
        let delta = rounded - posted
        posted = rounded
        return Int32(clamping: Int(delta))
    }

    /// Starts the next gesture from zero, keeping how fast the wheel was spinning.
    mutating func rebase() {
        target = 0
        head = 0
        base = 0
        position = 0
        posted = 0
        glideSpeed = 0
    }
}
