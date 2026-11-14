import AppKit
import Sparkle

/// Sparkle owns validation and installation; its user driver renders in our popover.
final class UpdateController: NSObject, SPUUpdaterDelegate, SPUUserDriver {
    private let model: AppModel
    private let canUpdate: () -> Bool
    private let presentUpdates: () -> Void
    private var updater: SPUUpdater!
    private var observations: [NSKeyValueObservation] = []
    private var cancellation: (() -> Void)?
    private var reply: ((SPUUserUpdateChoice) -> Void)?
    private var cancelChoice: SPUUserUpdateChoice = .dismiss
    private var retryTermination: (() -> Void)?
    private var expectedBytes: UInt64 = 0
    private var receivedBytes: UInt64 = 0

    init(model: AppModel, canUpdate: @escaping () -> Bool, presentUpdates: @escaping () -> Void = {}) {
        self.model = model
        self.canUpdate = canUpdate
        self.presentUpdates = presentUpdates
        super.init()
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in self?.refreshStatus() },
            updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, _ in self?.refreshStatus() }
        ]
    }

    func start() {
        do { try updater.start() }
        catch { model.updatePhase = .failed; model.updateStatus = error.localizedDescription }
        refreshStatus()
    }

    func refreshStatus() {
        model.automaticUpdates = updater.automaticallyChecksForUpdates
        model.canCheckForUpdates = updater.canCheckForUpdates
    }

    func setAutomaticChecks(_ enabled: Bool) {
        updater.automaticallyChecksForUpdates = enabled
        refreshStatus()
    }

    func checkForUpdates() {
        model.showUpdates = true
        guard updater.canCheckForUpdates else { return }
        updater.checkForUpdates()
    }

    func installUpdate() {
        guard canUpdate() else {
            model.updateStatus = "End your keep-awake session before installing."
            return
        }
        if let retryTermination {
            retryTermination()
            return
        }
        guard let reply else { return }
        let restarting = model.updatePhase == .ready
        clearActions()
        // Lock synchronously before Sparkle starts downloading or sends a quit event.
        model.updatePhase = restarting ? .installing : .downloading
        model.updateStatus = nil
        model.updateProgress = nil
        reply(.install)
    }

    func cancelUpdate() {
        let cancellation = self.cancellation
        let reply = self.reply
        guard cancellation != nil || reply != nil else { return }
        let choice = cancelChoice
        clearActions()
        model.updateStatus = "Canceling update…"
        // Keep any installation lock until Sparkle confirms the cycle has ended.
        if let cancellation { cancellation() } else { reply?(choice) }
    }

    private func clearActions() {
        cancellation = nil
        reply = nil
        retryTermination = nil
        model.canCancelUpdate = false
        model.canInstallUpdate = false
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        model.updatePhase = .checking
        model.updateStatus = "You can keep using Lid Less while we check."
        model.updateProgress = nil
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        clearActions()
        if model.updatePhase != .failed && model.updatePhase != .finished {
            model.updatePhase = .idle
            model.updateStatus = error?.localizedDescription
        }
        refreshStatus()
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // Automatic checks are explicitly opted into in Preferences.
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: model.automaticUpdates, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        clearActions()
        self.cancellation = cancellation
        model.canCancelUpdate = true
        model.updatePhase = .checking
        model.updateStatus = "You can keep using Lid Less while we check."
        model.updateProgress = nil
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        clearActions()
        self.reply = reply
        cancelChoice = state.stage == .installing ? .skip : .dismiss
        model.updateVersion = appcastItem.displayVersionString
        model.updatePhase = state.stage == .installing ? .ready : .available
        model.updateStatus = appcastItem.isInformationOnlyUpdate
            ? "This release requires a manual download. See the release notes."
            : "Your settings will be kept. Installation restarts Lid Less."
        model.canInstallUpdate = !appcastItem.isInformationOnlyUpdate
        model.canCancelUpdate = true
        model.updateProgress = nil
    }

    // Release notes are available through the repository link in the Updates view.
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool { false }

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        clearActions()
        model.updatePhase = .finished
        model.updateStatus = error.localizedDescription
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        clearActions()
        model.updatePhase = .failed
        model.updateStatus = error.localizedDescription
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        clearActions()
        self.cancellation = cancellation
        model.canCancelUpdate = true
        model.updatePhase = .downloading
        model.updateStatus = "New sessions are paused until you finish or cancel this update."
        expectedBytes = 0
        receivedBytes = 0
        model.updateProgress = nil
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedBytes = expectedContentLength
        updateDownloadProgress()
    }
    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedBytes += length
        updateDownloadProgress()
    }
    private func updateDownloadProgress() {
        model.updateProgress = expectedBytes > 0 ? min(1, Double(receivedBytes) / Double(expectedBytes)) : nil
    }

    func showDownloadDidStartExtractingUpdate() {
        clearActions()
        model.updatePhase = .extracting
        model.updateProgress = nil
        model.updateStatus = "Verifying and preparing the download."
    }
    func showExtractionReceivedProgress(_ progress: Double) { model.updateProgress = min(1, max(0, progress)) }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        clearActions()
        self.reply = reply
        cancelChoice = .skip // Cancel the prepared installer; do not leave an install-on-quit pending.
        model.updatePhase = .ready
        model.updateStatus = "Restart now to finish, or cancel to keep this version."
        model.canInstallUpdate = true
        model.canCancelUpdate = true
        model.updateProgress = nil
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        clearActions()
        model.updatePhase = .installing
        model.updateStatus = "Restoring normal sleep before restarting."
        if !applicationTerminated {
            retryTermination = retryTerminatingApplication
            model.canInstallUpdate = true
        }
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        clearActions()
        model.updatePhase = .finished
        model.updateStatus = "Update installed."
        acknowledgement()
    }

    func dismissUpdateInstallation() { clearActions() }
    func showUpdateInFocus() { model.showUpdates = true; presentUpdates() }
}
