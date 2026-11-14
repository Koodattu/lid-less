import AppKit
import SwiftUI

@main struct UIPreview {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let suite = "dev.lid-less.preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let model = AppModel(defaults: defaults)
        model.showWelcome = false
        model.duration = 7_200
        model.batteryPercent = 82
        model.onAC = false
        model.sensorAvailable = true
        model.toggleSession = {
            switch model.phase {
            case .idle: model.phase = .armed; model.secondsRemaining = 48
            case .armed: model.phase = .idle
            case .active: model.phase = .recovery; model.powerError = "macOS did not confirm sleep restoration. Retry, or restart your Mac if this continues."
            case .recovery: model.phase = .idle; model.powerError = nil
            }
        }
        model.checkForUpdates = {
            model.updatePhase = .checking
            model.updateStatus = "You can keep using Lid Less while we check."
            model.canCancelUpdate = true
        }
        model.cancelUpdate = { model.updatePhase = .idle; model.canCancelUpdate = false; model.updateStatus = nil }
        if CommandLine.arguments.contains("--update-ready") {
            model.showUpdates = true
            model.updatePhase = .ready
            model.canInstallUpdate = true
            model.canCancelUpdate = true
            model.updateStatus = "Restart now to finish, or cancel to keep this version."
        }
        model.changeLogin = { model.loginStatus = model.loginStatus == .enabled ? .notRegistered : .enabled }
        model.changeAutomaticUpdates = { model.automaticUpdates = $0 }
        model.quit = { app.terminate(nil) }
        let hosting = NSHostingView(rootView: PopoverView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 356, height: 540), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Lid Less UI Preview — simulated state"
        window.appearance = NSAppearance(named: .aqua)
        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        hosting.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hosting)
        NSLayoutConstraint.activate([hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor), hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor), hosting.topAnchor.constraint(equalTo: background.topAnchor), hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor)])
        window.contentView = background
        window.center()
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        app.run()
        defaults.removePersistentDomain(forName: suite)
    }
}
