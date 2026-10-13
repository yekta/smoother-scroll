import CoreGraphics
import Foundation
import IOKit.hid

/// Reads the wheel's own counts from the mouse. A fast spin puts several notches in one of its
/// reports, which macOS folds into one scroll event; its deltas are accelerated, so the count can
/// only be had from the report. Needs Input Monitoring access; without it every event is one notch.
///
/// Only touched on the engine's thread, where the manager is scheduled.
final class WheelReader {
    struct Report {
        var timestamp: UInt64
        var vertical: Int
        var horizontal: Int
    }

    /// How far apart an event's and its report's timestamps may be.
    private static let matchWindow: UInt64 = 20_000_000
    private var manager: IOHIDManager?
    private var reports: [Report] = []
    private let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(info.denom))
    }()

    static var hasAccess: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }

    @discardableResult
    static func requestAccess() -> Bool { IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }

    /// Starts, or starts over, on the current thread's run loop.
    func start() {
        stop()
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let mice: [[String: Int]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer],
        ]
        let wheels: [[String: Int]] = [
            [kIOHIDElementUsagePageKey: kHIDPage_GenericDesktop, kIOHIDElementUsageKey: kHIDUsage_GD_Wheel],
            [kIOHIDElementUsagePageKey: kHIDPage_Consumer, kIOHIDElementUsageKey: kHIDUsage_Csmr_ACPan],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, mice as CFArray)
        IOHIDManagerSetInputValueMatchingMultiple(manager, wheels as CFArray)
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            Unmanaged<WheelReader>.fromOpaque(context).takeUnretainedValue().record(value)
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
            return
        }
        self.manager = manager
    }

    func stop() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        reports.removeAll()
    }

    /// The notches the mouse sent in the report behind `event`, vertical and horizontal, or nil
    /// when none was seen. The report and what came before it are used up.
    func notches(for event: CGEvent) -> (vertical: Int, horizontal: Int)? {
        let timestamp = event.timestamp
        let distance = { (report: Report) in
            report.timestamp > timestamp ? report.timestamp - timestamp : timestamp - report.timestamp
        }
        guard let index = reports.indices.min(by: { distance(reports[$0]) < distance(reports[$1]) }),
              distance(reports[index]) <= Self.matchWindow else { return nil }
        let report = reports[index]
        reports.removeFirst(index + 1)
        return (abs(report.vertical), abs(report.horizontal))
    }

    private func record(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let count = IOHIDValueGetIntegerValue(value)
        guard count != 0 else { return }
        let timestamp = IOHIDValueGetTimeStamp(value) * timebase.numer / timebase.denom
        let vertical = IOHIDElementGetUsagePage(element) == kHIDPage_GenericDesktop
        if let last = reports.indices.last, reports[last].timestamp == timestamp {
            if vertical {
                reports[last].vertical += count
            } else {
                reports[last].horizontal += count
            }
            return
        }
        reports.append(Report(timestamp: timestamp, vertical: vertical ? count : 0, horizontal: vertical ? 0 : count))
        if reports.count > 64 {
            reports.removeFirst(reports.count - 64)
        }
    }
}
