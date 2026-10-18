import Foundation
import IOKit.hid

public final class LidAngleSensor {
    private let manager: IOHIDManager
    private var device: IOHIDDevice?

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: 0x05AC,
            kIOHIDDeviceUsagePageKey: 0x20,
            kIOHIDDeviceUsageKey: 0x8A,
        ] as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return }
        for candidate in devices {
            if IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess {
                device = candidate
                if read() != nil { break }
                IOHIDDeviceClose(candidate, IOOptionBits(kIOHIDOptionsTypeNone))
                device = nil
            }
        }
    }

    deinit {
        if let device { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    public func read() -> Double? {
        guard let device else { return nil }
        var bytes = [UInt8](repeating: 0, count: 8)
        var length = bytes.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &bytes, &length)
        guard result == kIOReturnSuccess else { return nil }
        return Self.decode(Array(bytes.prefix(length)))
    }

    public static func decode(_ report: [UInt8]) -> Double? {
        guard report.count >= 3, report[0] == 1 else { return nil }
        let degrees = Int(report[1]) | Int(report[2]) << 8
        guard degrees <= 180 else { return nil }
        return Double(degrees)
    }
}
