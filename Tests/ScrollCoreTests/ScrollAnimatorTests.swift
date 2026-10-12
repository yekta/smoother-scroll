import Foundation
import Testing
@testable import ScrollCore

private let frame = 1.0 / 120

/// Runs the animator over notches at the given times and returns every event it sends.
private func run(
    notches: [Double],
    direction: [Double]? = nil,
    settings: ScrollSettings = ScrollSettings(),
    until end: Double = 4
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

private func spin(rate: Double, count: Int) -> [Double] {
    (0..<count).map { Double($0) / rate }
}

private func total(_ events: [(time: Double, output: ScrollOutput)]) -> Int {
    events.reduce(0) { $0 + Int($1.output.dy) }
}

@Test func oneNotchLandsOnItsStep() {
    let events = run(notches: [0])
    #expect(total(events) == 250)
    let settledBy = run(notches: [0], until: 0.36)
    #expect(total(settledBy) >= 245)
}

@Test func notchesOneByOneDoNotGlide() {
    let events = run(notches: spin(rate: 3, count: 6))
    #expect(total(events) == 6 * 250)
}

@Test func aFastSpinGlidesOnLikeAFlick() {
    let notches = spin(rate: 15, count: 15)
    let events = run(notches: notches)
    #expect(total(events) > 15 * 250 + 500)
    let lastMove = events.filter { $0.output.moves }.map(\.time).max() ?? 0
    #expect(lastMove > notches.last! + 0.8)
}

@Test func motionNeverGoesBackwards() {
    for rate in [2.0, 6, 10, 20, 40] {
        let events = run(notches: spin(rate: rate, count: 20))
        #expect(events.allSatisfy { $0.output.dy >= 0 })
    }
}

@Test func reversingStopsTheGlide() {
    let notches = spin(rate: 15, count: 10) + [1.0]
    let direction = Array(repeating: 1.0, count: 10) + [-1]
    let events = run(notches: notches, direction: direction)
    let after = events.filter { $0.time > 1.0 && $0.output.moves }
    #expect(!after.isEmpty)
    #expect(after.allSatisfy { $0.output.dy < 0 })
}

@Test func accelerationOnlyForFastSpins() {
    let tuning = ScrollTuning(ScrollSettings())
    #expect(tuning.multiplier(rate: 10) == 1)
    #expect(tuning.multiplier(rate: 45) == 2)
    #expect(tuning.multiplier(rate: 10_000) == 10)
}

@Test func phasesFollowATrackpadGesture() {
    let events = run(notches: spin(rate: 15, count: 10)).map(\.output)
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

@Test func aNotchDuringMomentumEndsItFirst() {
    let events = run(notches: [0, 0.25]).map(\.output)
    let marks = events.filter { !($0.phase == .changed || $0.momentum == .changed) }
        .map { "\($0.phase.rawValue)/\($0.momentum.rawValue)" }
    #expect(marks == ["1/0", "4/0", "0/1", "0/3", "1/0", "4/0", "0/1", "0/3"])
}

@Test func withoutPhasesOnlyMovesAreSent() {
    var settings = ScrollSettings()
    settings.trackpadPhases = false
    let events = run(notches: spin(rate: 15, count: 10), settings: settings).map(\.output)
    #expect(events.allSatisfy { $0.moves && $0.phase == .none && $0.momentum == .none })
}

@Test func cancelEndsTheGesture() {
    let tuning = ScrollTuning(ScrollSettings())
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
    #expect(settings.animationTime == ScrollSettings().animationTime)
    #expect(settings.trackpadPhases)
}

@Test func bunchedEventsDoNotRunAway() {
    let bunched = (0..<6).flatMap { [Double($0) * 0.13, Double($0) * 0.13 + 0.002] }
    let even = spin(rate: 2 / 0.13, count: 12)
    let ratio = Double(total(run(notches: bunched))) / Double(total(run(notches: even)))
    #expect(abs(ratio - 1) < 0.25)
}
