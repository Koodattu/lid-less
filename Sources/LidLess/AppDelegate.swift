import AppKit
import LidLessCore
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let worker = WorkerSession()
    private lazy var controller = SessionController(power: worker)
    private let sensor = LidAngleSensor()
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let loginService = SMAppService.mainApp
    private var updater: UpdateController!
    private var timer: Timer?
    private var battery: (percent: Int?, onAC: Bool?) = (nil, nil)
    private var nextBatteryRead: TimeInterval = 0
    private var lastStatusSymbol = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverView(model: model))
        model.toggleSession = { [weak self] in self?.toggleSession() }
        model.changeLogin = { [weak self] in self?.toggleLaunchAtLogin() }
        model.openLoginSettings = { SMAppService.openSystemSettingsLoginItems() }
        model.quit = { NSApp.terminate(nil) }
        model.copyDiagnostics = { [weak self] in self?.copyDiagnostics() }
        updater = UpdateController(model: model, canUpdate: { [weak self] in self?.controller.state == .idle },
                                   presentUpdates: { [weak self] in self?.showPopover() })
        model.checkForUpdates = { [weak self] in self?.updater.checkForUpdates() }
        model.installUpdate = { [weak self] in self?.updater.installUpdate() }
        model.cancelUpdate = { [weak self] in self?.updater.cancelUpdate() }
        model.changeAutomaticUpdates = { [weak self] enabled in self?.updater.setAutomaticChecks(enabled) }
        updater.start()
        refreshLoginStatus()
        tick()
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.03
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        if model.showWelcome { showPopover() }
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }

    func popoverDidShow(_ notification: Notification) { updatePresentation() }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        refreshLoginStatus()
        updater?.refreshStatus()
        updatePresentation()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func refreshLoginStatus() { model.loginStatus = loginService.status }

    private func toggleLaunchAtLogin() {
        do {
            switch loginService.status {
            case .enabled, .requiresApproval: try loginService.unregister()
            case .notRegistered: try loginService.register()
            default: break
            }
            model.preferenceError = nil
        } catch { model.preferenceError = "Could not change Launch at Login: \(error.localizedDescription)" }
        refreshLoginStatus()
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if now >= nextBatteryRead {
            battery = SystemPower.battery()
            if model.batteryPercent != battery.percent { model.batteryPercent = battery.percent }
            if model.onAC != battery.onAC { model.onAC = battery.onAC }
            nextBatteryRead = now + 2
        }
        let angle = sensor.read()
        if model.sensorAvailable != (angle != nil) { model.sensorAvailable = angle != nil }
        let previous = controller.state
        controller.settings = model.settings
        do {
            if controller.state != .idle && controller.state != .recoveryRequired && !worker.isRunning {
                try controller.stop(reason: "Stopped — keep-awake worker exited")
                throw SessionError("The keep-awake worker exited. The lid override has been cleared.")
            }
            try controller.tick(now: now, lidClosed: SystemPower.lidClosed(), angle: angle,
                                optionHeld: model.gestureEnabled && !model.gesturePaused && !model.updateBlocksArming && NSEvent.modifierFlags.contains(.option),
                                batteryPercent: battery.percent, onAC: battery.onAC,
                                thermalCritical: ProcessInfo.processInfo.thermalState == .critical)
        } catch { reportPowerError(error) }
        if previous == .idle, case .armed = controller.state, model.soundEnabled {
            NSSound(named: "Tink")?.play()
        }
        updatePresentation()
    }

    private func updatePresentation() {
        let phase: AppModel.Phase
        let seconds: Int
        switch controller.state {
        case .idle: phase = .idle; seconds = 0
        case .armed(let deadline): phase = .armed; seconds = Int(ceil(max(0, deadline - ProcessInfo.processInfo.systemUptime)))
        case .active(let deadline): phase = .active; seconds = Int(ceil(max(0, deadline - ProcessInfo.processInfo.systemUptime)))
        case .recoveryRequired: phase = .recovery; seconds = 0
        }
        if model.phase != phase { model.phase = phase }
        if model.message != controller.message { model.message = controller.message }
        // Countdown rendering is needed only while the popover is visible.
        if popover.isShown, model.secondsRemaining != seconds { model.secondsRemaining = seconds }
        let symbol = model.powerError != nil ? "exclamationmark.triangle" : model.symbol
        if lastStatusSymbol != symbol {
            statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Lid Less: \(phase.rawValue)")
            lastStatusSymbol = symbol
        }
        statusItem.button?.toolTip = model.powerError ?? controller.message
        statusItem.button?.setAccessibilityLabel("Lid Less: \(controller.message)")
    }

    private func toggleSession() {
        guard !model.sessionActionDisabled else { return }
        do {
            if controller.state == .idle {
                battery = SystemPower.battery()
                controller.settings = model.settings
                try controller.arm(now: ProcessInfo.processInfo.systemUptime,
                                   lidClosed: SystemPower.lidClosed(), batteryPercent: battery.percent, onAC: battery.onAC,
                                   thermalCritical: ProcessInfo.processInfo.thermalState == .critical)
                model.gesturePaused = false
                if model.soundEnabled { NSSound(named: "Tink")?.play() }
            } else { try controller.stop() }
            model.powerError = nil
        } catch { reportPowerError(error) }
        updatePresentation()
    }

    private func reportPowerError(_ error: Error) {
        model.gesturePaused = true
        guard model.powerError != error.localizedDescription else { return }
        model.powerError = error.localizedDescription
        // Keep failures visible without interrupting work with a modal alert.
        // The status icon remains a warning even after the popover is dismissed.
    }

    private func copyDiagnostics() {
        let report = """
        Lid Less \(model.version)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Session: \(controller.message)
        Lid sensor: \(model.sensorAvailable ? "available" : "unavailable")
        Power: \(model.powerDescription)
        Login status: \(model.loginStatus.rawValue)
        Error: \(model.powerError ?? "none")
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        do {
            try controller.stop()
            timer?.invalidate()
            return .terminateNow
        } catch {
            reportPowerError(error)
            updatePresentation()
            showPopover()
            return .terminateCancel
        }
    }
}
