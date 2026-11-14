import AppKit
import Sparkle

/// Sparkle owns download validation, installation and relaunch. The delegate
/// prevents updates and lid sessions from overlapping, including background checks.
final class UpdateController: NSObject, SPUUpdaterDelegate {
    private let model: AppModel
    private let canUpdate: () -> Bool
    private var controller: SPUStandardUpdaterController!
    private var observations: [NSKeyValueObservation] = []

    init(model: AppModel, canUpdate: @escaping () -> Bool) {
        self.model = model
        self.canUpdate = canUpdate
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        observations = [
            controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in self?.refreshStatus() },
            controller.updater.observe(\.sessionInProgress, options: [.new]) { [weak self] _, _ in self?.refreshStatus() },
            controller.updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, _ in self?.refreshStatus() }
        ]
    }

    func start() {
        do { try controller.updater.start() }
        catch { model.updateStatus = "Updates unavailable: \(error.localizedDescription)" }
        refreshStatus()
    }

    func refreshStatus() {
        model.automaticUpdates = controller.updater.automaticallyChecksForUpdates
        model.canCheckForUpdates = controller.updater.canCheckForUpdates
        model.isUpdating = controller.updater.sessionInProgress
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
        refreshStatus()
    }

    func checkForUpdates() {
        guard canUpdate() else {
            model.updateStatus = "End the current session before checking for updates."
            return
        }
        guard controller.updater.canCheckForUpdates else { return }
        model.updateStatus = nil
        controller.checkForUpdates(nil)
        refreshStatus()
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard canUpdate() else {
            throw NSError(domain: "dev.lid-less.updates", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Updates wait until your keep-awake session ends."])
        }
        // Set synchronously before returning so Option-close cannot race a check.
        model.isUpdating = true
    }

    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        guard canUpdate() else {
            throw NSError(domain: "dev.lid-less.updates", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "End your keep-awake session before installing an update."])
        }
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        model.updateStatus = error.localizedDescription
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        refreshStatus()
    }
}
