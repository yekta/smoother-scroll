import Foundation
import Testing
@testable import ScrollCore

private let frame = 1.0 / 120

/// Runs the animator over notches at the given times and returns every event it sends.
private func run(
    notches: [Double],
    direction: [Double]? = nil,
    settings: ScrollSettings = ScrollSettings(),
    until end: Double = 3
) -> [(time: Double, output: ScrollOutput)] {
    let tuning = ScrollTuning(settings)
    var animator = ScrollAnimator()
    var events: [(Double, ScrollOutput)] = []
    var next = 0
    var time = 0.0
    while time < end {
        while next < notches.count, notches[next] <= time {
            animator.notch(dx: 0, dy: direction?[next] ?? 1, at: notches[next], tuning: tuning)
            next += 1
        }
        for output in animator.advance(to: time, tuning: tuning) {
            events.append((time, output))
        }
        time += frame
    }
    return events
}

private func spin(every interval: Double, count: Int) -> [Double] {
    (0..<count).map { Double($0) * interval }
}

private func total(_ events: [(time: Double, output: ScrollOutput)]) -> Int {
    events.reduce(0) { $0 + Int($1.output.dy) }
}

private var withTrackpadExtras: ScrollSettings {
    var settings = ScrollSettings()
    settings.momentum = 0.5
    settings.trackpadPhases = true
    return settings
}

@Test func oneNotchMovesItsStepOverTheAnimationTime() {
    let events = run(notches: [0])
    #expect(total(events) == 250)
    let lastMove = events.filter { $0.output.moves }.map(\.time).max() ?? 0
    #expect(lastMove <= 0.35 + frame)
}

@Test func aNotchFollowsThePulse() {
    let tuning = ScrollTuning(ScrollSettings())
    let halfway = run(notches: [0], until: 0.175 + frame / 2)
    #expect(abs(Double(total(halfway)) - 250 * tuning.ease(0.5)) <= 1)
    #expect(tuning.ease(0) == 0)
    #expect(tuning.ease(1) == 1)
    #expect(tuning.ease(0.1) < 0.1)
    #expect(tuning.ease(0.5) > 0.5)
}

@Test func motionNeverGoesBackwards() {
    for interval in [0.5, 0.15, 0.08, 0.04, 0.01] {
        let events = run(notches: spin(every: interval, count: 20))
        #expect(events.allSatisfy { $0.output.dy >= 0 })
    }
}

@Test func reversingStopsWhatIsLeft() {
    let notches = spin(every: 0.06, count: 6) + [0.4]
    let direction = Array(repeating: 1.0, count: 6) + [-1]
    let events = run(notches: notches, direction: direction)
    let after = events.filter { $0.time > 0.4 && $0.output.moves }
    #expect(!after.isEmpty)
    #expect(after.allSatisfy { $0.output.dy < 0 })
}

@Test func byDefaultNothingMovesAfterTheLastNotchEnds() {
    let notches = spin(every: 0.06, count: 15)
    let events = run(notches: notches)
    let lastMove = events.filter { $0.output.moves }.map(\.time).max() ?? 0
    #expect(lastMove <= notches.last! + 0.35 + frame)
    #expect(events.allSatisfy { $0.output.phase == .none && $0.output.momentum == .none })
}

@Test func withMomentumAFastSpinGlidesOn() {
    let notches = spin(every: 1.0 / 15, count: 15)
    let plain = total(run(notches: notches))
    let events = run(notches: notches, settings: withTrackpadExtras)
    #expect(total(events) > plain + 500)
    let lastMove = events.filter { $0.output.moves }.map(\.time).max() ?? 0
    #expect(lastMove > notches.last! + 0.8)
}

@Test func withMomentumNotchesOneByOneDoNotGlide() {
    let events = run(notches: spin(every: 0.4, count: 4), settings: withTrackpadExtras)
    #expect(total(events) == 4 * 250)
}

@Test func trackpadPhasesFollowAGesture() {
    let events = run(notches: spin(every: 1.0 / 15, count: 10), settings: withTrackpadExtras).map(\.output)
    var phases = events.map { output -> String in
        switch (output.phase, output.momentum) {
        case (.began, _): return "B"
        case (.changed, _): return "C"
        case (.ended, _): return "E"
        case (_, .began): return "b"
        case (_, .changed): return "c"
        case (_, .ended): return "e"
        default: return "?"
        }
    }.joined()
    phases = phases.replacingOccurrences(of: "C+", with: "C", options: .regularExpression)
    phases = phases.replacingOccurrences(of: "c+", with: "c", options: .regularExpression)
    #expect(phases == "BCEbce")
}

@Test func cancelEndsTheGesture() {
    let tuning = ScrollTuning(withTrackpadExtras)
    var animator = ScrollAnimator()
    animator.notch(dx: 0, dy: 1, at: 0, tuning: tuning)
    _ = animator.advance(to: frame, tuning: tuning)
    let out = animator.cancel(tuning: tuning)
    #expect(out == [ScrollOutput(dx: 0, dy: 0, phase: .ended, momentum: .none)])
    #expect(animator.isIdle)
}

@Test func savedSettingsKeepTheirValuesAndFillInNewOnes() throws {
    let saved = #"{"stepSize": 120, "reverseDirection": true}"#.data(using: .utf8)!
    let settings = try JSONDecoder().decode(ScrollSettings.self, from: saved)
    #expect(settings.stepSize == 120)
    #expect(settings.reverseDirection)
    #expect(settings.animationTime == 350)
    #expect(settings.acceleration == 1)
    #expect(!settings.trackpadPhases)
}

/// The distance of `count` notches spread evenly over `seconds`, timed by the mouse's clock.
private func distance(of count: Int, over seconds: Double, settings: ScrollSettings = ScrollSettings()) -> Int {
    let interval = seconds / Double(count)
    let tuning = ScrollTuning(settings)
    var animator = ScrollAnimator()
    var moved = 0
    var next = 0
    var time = 0.0
    while time < seconds + 1 {
        while next < count, Double(next) * interval <= time {
            animator.notch(dx: 0, dy: 1, at: Double(next) * interval, sinceLastNotch: next == 0 ? nil : interval, tuning: tuning)
            next += 1
        }
        moved += animator.advance(to: time, tuning: tuning).reduce(0) { $0 + Int($1.dy) }
        time += frame
    }
    return moved
}

@Test func slowNotchesMoveExactlyTheirStep() {
    #expect(distance(of: 10, over: 4) == 2500)
}

@Test func theFasterTheWheelSpinsTheFurtherEachNotchGoes() {
    let slow = distance(of: 10, over: 2)
    let medium = distance(of: 10, over: 1)
    let fast = distance(of: 10, over: 0.5)
    let flick = distance(of: 10, over: 0.2)
    #expect(slow < medium && medium < fast && fast < flick)
    #expect(flick > 8 * slow)
}

@Test func accelerationFollowsItsCurveUpToTheMaximum() {
    let tuning = ScrollTuning(ScrollSettings())
    #expect(tuning.multiplier(rate: 3) == 1)
    #expect(abs(tuning.multiplier(rate: 10) - 1.59) < 0.01)
    #expect(tuning.multiplier(rate: 500) == 20)
    var off = ScrollSettings()
    off.acceleration = 0
    #expect(distance(of: 10, over: 0.2, settings: off) == 2500)
}

@Test func notchesSentTogetherCountAsSpreadOut() {
    #expect(ScrollAnimator.rate(of: [0, 0.0001]) == 1 / ScrollTuning.closestNotches)
}

@Test func speedIsMeasuredByWhenTheMouseSentTheNotches() {
    let tuning = ScrollTuning(ScrollSettings())
    var animator = ScrollAnimator()
    animator.notch(dx: 0, dy: 1, at: 0, tuning: tuning)
    animator.notch(dx: 0, dy: 1, at: 0.001, sinceLastNotch: 0.5, tuning: tuning)
    var moved = 0
    for frame in 1...60 {
        moved += animator.advance(to: Double(frame) / 120, tuning: tuning).reduce(0) { $0 + Int($1.dy) }
    }
    #expect(moved == 500)
}

