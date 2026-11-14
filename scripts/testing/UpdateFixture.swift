import AppKit

/// Exercises the production user driver without any power-management code.
final class Delegate: NSObject, NSApplicationDelegate {
    var updater: UpdateController!
    var timer: Timer?
    let model = AppModel()
    private var lastPhase: AppModel.UpdatePhase?
    private var canceled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "2" {
            let path = Bundle.main.object(forInfoDictionaryKey: "FixtureResultPath") as! String
            try! "Updated and relaunched".write(toFile: path, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
            return
        }
        updater = UpdateController(model: model, canUpdate: { true })
        updater.start()
        updater.checkForUpdates()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [self] _ in
            if lastPhase != model.updatePhase {
                print("Update phase: \(model.updatePhase)"); fflush(stdout)
                lastPhase = model.updatePhase
            }
            let mode = Bundle.main.object(forInfoDictionaryKey: "FixtureMode") as? String
            if !canceled && ((mode == "cancel-check" && model.updatePhase == .checking) || (mode == "cancel-ready" && model.updatePhase == .ready)) {
                canceled = true
                updater.cancelUpdate()
                return
            }
            if canceled && model.updatePhase == .idle {
                precondition(!model.sessionActionDisabled)
                let path = Bundle.main.object(forInfoDictionaryKey: "FixtureResultPath") as! String
                try! "Canceled without reopening".write(toFile: path, atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
                return
            }
            switch model.updatePhase {
            case .available, .ready: updater.installUpdate()
            case .failed: print("ERROR: \(model.updateStatus ?? "unknown")"); fflush(stdout); exit(3)
            case .finished: print(model.updateStatus ?? "Finished without relaunch"); fflush(stdout); exit(2)
            default: break
            }
        }
    }
}

@main struct UpdateFixture {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = Delegate()
        app.delegate = delegate
        app.run()
    }
}
