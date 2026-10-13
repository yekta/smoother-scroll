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
    #expect(total(events) == 150)
    let lastMove = events.filter { $0.output.moves }.map(\.time).max() ?? 0
    #expect(lastMove <= 0.35 + frame)
}

@Test func aNotchFollowsItsEasing() {
    let tuning = ScrollTuning(ScrollSettings())
    let halfway = run(notches: [0], until: 0.175 + frame / 2)
    #expect(abs(Double(total(halfway)) - 150 * tuning.ease(0.5)) <= 1)
    #expect(tuning.ease(0) == 0)
    #expect(tuning.ease(1) == 1)
}

@Test func byDefaultANotchFollowsApplesEaseInEaseOut() {
    let tuning = ScrollTuning(ScrollSettings())
    for x in stride(from: 0.0, through: 1.0, by: 0.05) {
        #expect(abs(tuning.ease(x) - CubicBezier.easeInEaseOut.value(at: x)) < 1e-9)
    }
}

@Test func applesCurvesHaveTheirKnownValues() {
    #expect(abs(CubicBezier.easeInEaseOut.value(at: 0.5) - 0.5) < 1e-6)
    #expect(abs(CubicBezier.easeInEaseOut.value(at: 0.25) - 0.1291) < 0.001)
    #expect(abs(CubicBezier.easeIn.value(at: 0.5) - 0.3153) < 0.001)
    #expect(abs(CubicBezier.easeOut.value(at: 0.5) - 0.6847) < 0.001)
}

@Test func aLongerEaseOutSlowsDownForLongerWithoutAJolt() {
    var settings = ScrollSettings()
    settings.tailToHeadRatio = 3
    let tuning = ScrollTuning(settings)
    let head = 0.25
    let before = (tuning.ease(head) - tuning.ease(head - 1e-4)) / 1e-4
    let after = (tuning.ease(head + 1e-4) - tuning.ease(head)) / 1e-4
    #expect(abs(before - after) < 0.01)
    #expect(abs(tuning.ease(head) - head) < 1e-9)
}

@Test func eachEasingCanBeTurnedOff() {
    var settings = ScrollSettings()
    settings.easeIn = false
    #expect(ScrollTuning(settings).ease(0.5) == CubicBezier.easeOut.value(at: 0.5))
    settings.easeIn = true
    settings.easeOut = false
    #expect(ScrollTuning(settings).ease(0.5) == CubicBezier.easeIn.value(at: 0.5))
    settings.easeIn = false
    #expect(ScrollTuning(settings).ease(0.3) == 0.3)
}

@Test func motionNeverGoesBackwards() {
    for interval in [0.5, 0.15, 0.08, 0.04, 0.01] {
        let events = run(notches: spin(every: interval, count: 20))
        #expect(events.allSatisfy { $0.output.dy >= 0 })
    }
}

@Test func reversingStopsWhatIsLeft() {
    let notches = spin(every: 0.06, count: 6) + [0.5]
    let direction = Array(repeating: 1.0, count: 6) + [-1]
    let events = run(notches: notches, direction: direction)
    let after = events.filter { $0.time > 0.5 && $0.output.moves }
    #expect(!after.isEmpty)
    #expect(after.allSatisfy { $0.output.dy < 0 })
}

@Test func aBounceTheOtherWayInAFastSpinIsIgnored() {
    var notches = spin(every: 0.03, count: 20)
    var direction = Array(repeating: 1.0, count: 20)
    notches.insert(0.31, at: 11)
    direction.insert(-1, at: 11)
    let clean = total(run(notches: spin(every: 0.03, count: 20)))
    let events = run(notches: notches, direction: direction)
    #expect(events.allSatisfy { $0.output.dy >= 0 })
    #expect(abs(total(events) - clean) < clean / 20)
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
    #expect(total(events) == 4 * 150)
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
    #expect(distance(of: 10, over: 4) == 1500)
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
    #expect(distance(of: 10, over: 0.2, settings: off) == 1500)
}

@Test func notchesSentTogetherCountAsSpreadOut() {
    #expect(ScrollAnimator.rate(of: [0, 0.0001]) == 1 / ScrollTuning.closestNotches)
}

@Test func notchesInOneEventGoAsFarAsSentApart() {
    let apart = distance(of: 10, over: 0.5)
    let tuning = ScrollTuning(ScrollSettings())
    var animator = ScrollAnimator()
    var moved = 0
    var next = 0
    var time = 0.0
    while time < 2 {
        while next < 5, Double(next) * 0.1 <= time {
            animator.notch(dx: 0, dy: 2, at: Double(next) * 0.1, sinceLastNotch: next == 0 ? nil : 0.1, tuning: tuning)
            next += 1
        }
        moved += animator.advance(to: time, tuning: tuning).reduce(0) { $0 + Int($1.dy) }
        time += frame
    }
    #expect(moved > 2 * 1500)
    #expect(abs(moved - apart) < apart / 10)
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
    #expect(moved == 300)
}

