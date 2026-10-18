import AppKit
import LidLessCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let worker = WorkerSession()
    private lazy var controller = SessionController(power: worker)
    private let sensor = LidAngleSensor()
    private var statusItem: NSStatusItem!
    private let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let gestureStatus = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let toggle = NSMenuItem(title: "Arm for Next Close", action: #selector(toggleSession), keyEquivalent: "")
    private var timer: Timer?
    private var battery: (percent: Int?, onAC: Bool?) = (nil, nil)
    private var nextBatteryRead: TimeInterval = 0
    private var automaticGestureEnabled = true
    private var lastError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Launch Services normally prevents duplicates; this also handles direct launches.
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "Lid Less")
        let menu = NSMenu()
        menu.autoenablesItems = false
        let title = NSMenuItem(title: "Lid Less · Experimental", action: nil, keyEquivalent: "")
        title.isEnabled = false
        status.isEnabled = false
        gestureStatus.isEnabled = false
        menu.addItem(title)
        menu.addItem(status)
        menu.addItem(.separator())
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(gestureStatus)
        let limits = NSMenuItem(title: "Stops on reopen, at 15% battery, or after 8 hours", action: nil, keyEquivalent: "")
        limits.isEnabled = false
        menu.addItem(limits)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Lid Less", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        tick()
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.03
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if now >= nextBatteryRead {
            battery = SystemPower.battery()
            nextBatteryRead = now + 2
        }
        let angle = sensor.read()
        do {
            if controller.state != .idle && controller.state != .recoveryRequired && !worker.isRunning {
                try controller.stop(reason: "Stopped — keep-awake worker exited")
                throw SessionError("The keep-awake worker exited. The lid override has been cleared.")
            }
            try controller.tick(now: now, lidClosed: SystemPower.lidClosed(), angle: angle,
                                optionHeld: automaticGestureEnabled && NSEvent.modifierFlags.contains(.option),
                                batteryPercent: battery.percent, onAC: battery.onAC,
                                thermalCritical: ProcessInfo.processInfo.thermalState == .critical)
        } catch { showError(error) }
        updateMenu(angle: angle)
    }

    private func updateMenu(angle: Double?) {
        status.title = lastError == nil ? controller.message : "Error — \(controller.message)"
        toggle.title = controller.state == .idle ? "Arm for Next Close" : "Disarm / Restore Sleep"
        gestureStatus.title = !automaticGestureEnabled ? "Option-close paused — arm manually to retry" :
            (angle == nil ? "Lid angle unavailable — use Arm for Next Close" : "Hold ⌥ Option while lowering the lid")
        statusItem.button?.title = controller.state == .idle ? "" : " ON"
        statusItem.button?.toolTip = lastError ?? controller.message
    }

    @objc private func toggleSession() {
        do {
            if controller.state == .idle {
                battery = SystemPower.battery()
                try controller.arm(now: ProcessInfo.processInfo.systemUptime,
                                   lidClosed: SystemPower.lidClosed(), batteryPercent: battery.percent, onAC: battery.onAC)
                automaticGestureEnabled = true
            } else { try controller.stop() }
            lastError = nil
        } catch { showError(error) }
        updateMenu(angle: sensor.read())
    }

    private func showError(_ error: Error) {
        automaticGestureEnabled = false
        guard lastError != error.localizedDescription else { return }
        lastError = error.localizedDescription
        let alert = NSAlert()
        alert.messageText = "Lid Less needs attention"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        // Modal alerts run a nested run loop; stop sampling to avoid re-entry.
        timer?.fireDate = .distantFuture
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        timer?.fireDate = Date().addingTimeInterval(0.15)
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        do {
            try controller.stop()
            timer?.invalidate()
            return .terminateNow
        } catch {
            showError(error)
            return .terminateCancel
        }
    }
}
