import AppKit
import Darwin
import LidLessCore

// A broken worker pipe must be handled as an error, not terminate the UI.
signal(SIGPIPE, SIG_IGN)

switch CommandLine.arguments.dropFirst().first {
case "--hold-worker":
    exit(runWorker())
case "--diagnose":
    let sensor = LidAngleSensor()
    let battery = SystemPower.battery()
    print("Lid closed: \(SystemPower.lidClosed().map(String.init) ?? "unavailable")")
    print("Lid angle: \(sensor.read().map { "\($0)°" } ?? "unavailable")")
    print("Battery: \(battery.percent.map { "\($0)%" } ?? "unavailable")")
    print("AC power: \(battery.onAC.map(String.init) ?? "unavailable")")
    print("Read-only diagnostics; no sleep settings changed.")
case "--restore":
    do {
        try SystemPower().restoreLidSleep()
        print("Lid-sleep restoration request accepted by macOS.")
    } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
        exit(1)
    }
case nil:
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
default:
    print("Usage: LidLess [--diagnose | --restore]")
    exit(2)
}
