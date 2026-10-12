import AppKit
import QuartzCore
import ScrollCore
import os

/// Catches the wheel's scroll events and posts smooth ones in their place.
///
/// The event tap and the display link both run on one thread of their own, so the animator is
/// only ever touched there and a busy main thread can't make scrolling stutter.
final class ScrollEngine: NSObject, @unchecked Sendable {
    /// Marks the events we post, so the tap lets them through.
    private static let marker: Int64 = 0x5353_4352_4F4C_4C

    private let settings = OSAllocatedUnfairLock(initialState: ScrollSettings())
    private let excluded = OSAllocatedUnfairLock(initialState: Set<String>())
    private var thread: Thread?
    private var tap: CFMachPort?

    // Only touched on the engine's thread.
    private var animator = ScrollAnimator()
    private var tuning = ScrollTuning(ScrollSettings())
    private var link: CADisplayLink?
    private var linkDisplay: CGDirectDisplayID = 0
    private var flags: CGEventFlags = []
    private var lastLookup = (time: -Double.infinity, excluded: false)

    var isRunning: Bool { tap != nil }

    func update(_ newSettings: ScrollSettings) {
        settings.withLock { $0 = newSettings }
        excluded.withLock { $0 = Set(newSettings.excludedApps.map(\.bundleID)) }
    }

    /// Starts catching scroll events. Fails until the app has Accessibility access.
    @MainActor
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let engine = Unmanaged<ScrollEngine>.fromOpaque(info).takeUnretainedValue()
            return engine.handle(type: type, event: event)
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        tap = port

        let thread = Thread { [weak self] in
            guard let self, let port = self.tap else { return }
            let source = CFMachPortCreateRunLoopSource(nil, port, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
        }
        thread.name = "Smoother Scroll"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread
        linkDisplay = CGMainDisplayID()
        installLink(for: linkDisplay)
        return true
    }

    // MARK: Engine thread

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        case .scrollWheel:
            return handleScroll(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleScroll(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        guard event.getIntegerValueField(.eventSourceUserData) != Self.marker else { return pass }

        let current = settings.withLock { $0 }
        let newTuning = ScrollTuning(current)
        if newTuning != tuning {
            tuning = newTuning
        }

        // A trackpad or a Magic Mouse already scrolls smoothly; touching one stops our glide.
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else {
            stopAnimation()
            return pass
        }
        guard current.enabled else { return pass }
        // Zooming and the like expect the wheel's own steps.
        guard event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty else {
            stopAnimation()
            return pass
        }

        var dy = notches(event, axis: .scrollWheelEventFixedPtDeltaAxis1)
        var dx = notches(event, axis: .scrollWheelEventFixedPtDeltaAxis2)
        if event.flags.contains(.maskShift), dx == 0 {
            swap(&dx, &dy)
        }
        if !current.smoothHorizontal, dx != 0 {
            guard dy != 0 else { return pass }
            dx = 0
        }
        guard dx != 0 || dy != 0 else { return pass }
        guard !isExcluded(at: event.location) else { return pass }

        if current.reverseDirection {
            dx = -dx
            dy = -dy
        }
        flags = event.flags.subtracting(.maskShift)
        if animator.isIdle {
            followDisplay(at: event.location)
        }
        animator.notch(dx: dx, dy: dy, at: CACurrentMediaTime(), tuning: tuning)
        link?.isPaused = false
        return nil
    }

    /// One event is one notch. macOS speeds up the wheel's own deltas; we only keep their sign,
    /// and the fraction of a notch that high-resolution wheels send.
    private func notches(_ event: CGEvent, axis: CGEventField) -> Double {
        var value = event.getDoubleValueField(axis)
        if value == 0 {
            let line: CGEventField = axis == .scrollWheelEventFixedPtDeltaAxis1 ? .scrollWheelEventDeltaAxis1 : .scrollWheelEventDeltaAxis2
            value = Double(event.getIntegerValueField(line))
        }
        guard value != 0 else { return 0 }
        return value > 0 ? min(value, 1) : max(value, -1)
    }

    private func isExcluded(at point: CGPoint) -> Bool {
        let list = excluded.withLock { $0 }
        guard !list.isEmpty else { return false }
        let now = CACurrentMediaTime()
        if !animator.isIdle, now - lastLookup.time < 0.5 {
            return lastLookup.excluded
        }
        let bundleID = AppLookup.bundleID(at: point)
        let isExcluded = bundleID.map(list.contains) ?? false
        lastLookup = (now, isExcluded)
        return isExcluded
    }

    private func stopAnimation() {
        guard !animator.isIdle else { return }
        post(animator.cancel(tuning: tuning))
        link?.isPaused = true
    }

    @objc private func frame(_ link: CADisplayLink) {
        post(animator.advance(to: link.targetTimestamp, tuning: tuning))
        if animator.isIdle {
            link.isPaused = true
        }
    }

    private func post(_ outputs: [ScrollOutput]) {
        for output in outputs {
            guard let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: output.dy,
                wheel2: output.dx,
                wheel3: 0
            ) else { continue }
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: output.phase.rawValue)
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: output.momentum.rawValue)
            event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            event.flags = flags
            event.post(tap: .cgSessionEventTap)
        }
    }

    // MARK: Display link

    /// Frames come from the display the pointer is on, at its refresh rate.
    private func followDisplay(at point: CGPoint) {
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &display, &count) == .success, count > 0 else { return }
        guard display != linkDisplay else { return }
        linkDisplay = display
        installLink(for: display)
    }

    private func installLink(for display: CGDirectDisplayID) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let thread = self.thread else { return }
            let screen = NSScreen.screens.first { $0.displayID == display } ?? NSScreen.main
            guard let link = screen?.displayLink(target: self, selector: #selector(self.frame(_:))) else { return }
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            self.perform(#selector(self.attach(_:)), on: thread, with: link, waitUntilDone: false)
        }
    }

    @objc private func attach(_ newLink: CADisplayLink) {
        let wasRunning = link.map { !$0.isPaused } ?? false
        link?.invalidate()
        newLink.add(to: .current, forMode: .common)
        newLink.isPaused = !wasRunning && animator.isIdle
        link = newLink
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
