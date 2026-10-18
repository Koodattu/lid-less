import Foundation
import IOKit
import IOKit.pwr_mgt
import IOKit.ps

public final class SystemPower: SleepOverride {
    private var connection: io_connect_t = 0
    private var assertion: IOPMAssertionID?
    private var needsRestore = false

    public init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { throw SessionError("macOS power manager was not found.") }
        defer { IOObjectRelease(service) }
        try check(IOServiceOpen(service, mach_task_self_, 0, &connection), "Open power manager")
    }

    deinit { if connection != 0 { IOServiceClose(connection) } }

    public func start() throws {
        if assertion == nil {
            var identifier: IOPMAssertionID = 0
            try check(IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Lid Less closed-lid session" as CFString, &identifier
            ), "Prevent idle sleep")
            assertion = identifier
        }
        needsRestore = true
        try setLidSleepDisabled(true)
    }

    public func refresh() throws { try setLidSleepDisabled(true) }

    public func stop() throws {
        var restoreError: Error?
        if needsRestore {
            do { try restoreLidSleep(); needsRestore = false }
            catch { restoreError = error }
        }
        // Release idle inhibition even when lid restoration failed.
        if let assertion {
            let result = IOPMAssertionRelease(assertion)
            if result == kIOReturnSuccess { self.assertion = nil }
            else if restoreError == nil {
                restoreError = SessionError("Release idle assertion failed (\(result)).")
            }
        }
        if let restoreError { throw restoreError }
    }

    public func restoreLidSleep() throws {
        var lastError: Error?
        for _ in 0..<3 {
            do { try setLidSleepDisabled(false); return }
            catch { lastError = error }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw lastError!
    }

    private func setLidSleepDisabled(_ disabled: Bool) throws {
        var input: UInt64 = disabled ? 1 : 0
        var outputCount: UInt32 = 0
        // IOPMLibDefs.h selector; Apple XNU RootDomainUserClient dispatches this
        // without a privilege check. It is shared state, not a scoped assertion.
        try check(IOConnectCallScalarMethod(connection, UInt32(kPMSetClamshellSleepState),
                                            &input, 1, nil, &outputCount),
                  disabled ? "Override lid-close sleep" : "Restore lid-close sleep")
    }

    private func check(_ result: IOReturn, _ operation: String) throws {
        guard result == kIOReturnSuccess else {
            throw SessionError("\(operation) failed (\(String(format: "0x%08x", UInt32(bitPattern: result)))).")
        }
    }

    public static func lidClosed() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString,
                                               kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
    }

    public static func battery() -> (percent: Int?, onAC: Bool?) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return (nil, nil)
        }
        for source in sources {
            guard let details = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  details[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = details[kIOPSCurrentCapacityKey] as? Int
            let maximum = details[kIOPSMaxCapacityKey] as? Int
            let percent = current.flatMap { value in maximum.flatMap { $0 > 0 ? value * 100 / $0 : nil } }
            let onAC = (details[kIOPSPowerSourceStateKey] as? String).map { $0 == kIOPSACPowerValue }
            return (percent, onAC)
        }
        return (nil, nil)
    }
}
