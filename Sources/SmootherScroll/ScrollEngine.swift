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
    private var lastNotchTimestamp: CGEventTimestamp = 0
    private var lastLookup = (time: -Double.infinity, excluded: false)
    private let wheel = WheelReader()
    private let log = WheelLog()

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
            self.wheel.start()
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

    /// Starts reading the wheel's counts over again, once Input Monitoring access is given.
    func reopenWheel() {
        guard let thread else { return }
        perform(#selector(startWheel), on: thread, with: nil, waitUntilDone: false)
    }

    // MARK: Engine thread

    @objc private func startWheel() {
        wheel.start()
    }

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
        var smoothed: (dx: Double, dy: Double)?
        defer { log.write(event, notch: smoothed) }

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
        // Taken for every wheel event, so passed ones do not leave their reports behind.
        let counts = wheel.notches(for: event)
        guard current.enabled else { return pass }
        // Zooming and the like expect the wheel's own steps.
        guard event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty else {
            stopAnimation()
            return pass
        }

        var (dx, dy) = notch(of: event, counts: counts)
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
        // How far apart notches came is read from when the mouse sent them: they can reach the tap
        // bunched, and acceleration divides by it.
        let timestamp = event.timestamp
        let sinceLast = timestamp > lastNotchTimestamp ? Double(timestamp - lastNotchTimestamp) / 1e9 : nil
        lastNotchTimestamp = timestamp
        smoothed = (dx, dy)
        animator.notch(dx: dx, dy: dy, at: CACurrentMediaTime(), sinceLastNotch: sinceLast, tuning: tuning)
        link?.isPaused = false
        return nil
    }

    /// One event is as many whole notches as the mouse's report says, or one without it, along its
    /// main axis. macOS sends a slow notch as a fraction of a line (about 0.1) and a fast one as
    /// many lines; taking those literally made a slow notch a tenth of its step. How fast the
    /// wheel spins is ours to measure.
    private func notch(of event: CGEvent, counts: (vertical: Int, horizontal: Int)?) -> (dx: Double, dy: Double) {
        let vertical = lines(event, .scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1)
        let horizontal = lines(event, .scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2)
        guard vertical != 0 || horizontal != 0 else { return (0, 0) }
        guard abs(horizontal) > abs(vertical) else {
            let count = Double(max(counts?.vertical ?? 1, 1))
            return (0, vertical > 0 ? count : -count)
        }
        let count = Double(max(counts?.horizontal ?? 1, 1))
        return (horizontal > 0 ? count : -count, 0)
    }

    private func lines(_ event: CGEvent, _ whole: CGEventField, _ fraction: CGEventField) -> Double {
        let fixed = event.getDoubleValueField(fraction)
        guard fixed == 0 else { return fixed }
        return Double(event.getIntegerValueField(whole))
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
