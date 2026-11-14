import AppKit
import Sparkle

/// An isolated test app. It has no power-management code and only updates itself.
final class Driver: NSObject, SPUUserDriver {
    private func log(_ message: String) { print(message); fflush(stdout) }
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) { reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false)) }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { log("Checking") }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) { log("Found update \(appcastItem.versionString)"); reply(.install) }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { log("No update: \(error)"); acknowledgement(); exit(2) }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) { log("ERROR: \(error)"); acknowledgement(); exit(3) }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { log("Downloading") }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() { log("Extracting") }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { log("Installing"); reply(.install) }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) { log("Terminated: \(applicationTerminated)") }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { log("Installed"); acknowledgement() }
    func dismissUpdateInstallation() {}
}

final class Delegate: NSObject, NSApplicationDelegate {
    let driver = Driver()
    var updater: SPUUpdater!
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "2" {
            let path = Bundle.main.object(forInfoDictionaryKey: "FixtureResultPath") as! String
            try! "Updated and relaunched".write(toFile: path, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
            return
        }
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: nil)
        do { try updater.start() } catch { print(error); exit(4) }
        updater.checkForUpdates()
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
