import XCTest
import Sparkle
@testable import LidLess

final class AppModelTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "dev.lid-less.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    func testPreferencesPersistButSessionStateDoesNot() {
        let model = AppModel(defaults: defaults)
        XCTAssertEqual(model.duration, 28_800)
        XCTAssertEqual(model.batteryFloor, 15)
        XCTAssertTrue(model.gestureEnabled)
        XCTAssertFalse(model.soundEnabled)
        model.duration = 3_600
        model.batteryFloor = 25
        model.gestureEnabled = false
        model.soundEnabled = true
        model.phase = .active
        model.dismissWelcome()
        let next = AppModel(defaults: defaults)
        XCTAssertEqual(next.duration, 3_600)
        XCTAssertEqual(next.batteryFloor, 25)
        XCTAssertFalse(next.gestureEnabled)
        XCTAssertTrue(next.soundEnabled)
        XCTAssertFalse(next.showWelcome)
        XCTAssertEqual(next.phase, .idle)
    }

    func testInvalidPreferencesAreNormalized() {
        defaults.set(-1, forKey: "sessionDuration")
        defaults.set(0, forKey: "batteryFloor")
        let model = AppModel(defaults: defaults)
        XCTAssertEqual(model.duration, 28_800)
        XCTAssertEqual(model.batteryFloor, 15)
    }

    func testCountdownAndRecoveryAction() {
        let model = AppModel(defaults: defaults)
        model.phase = .armed
        model.secondsRemaining = 59
        XCTAssertEqual(model.countdown, "Close within 59s")
        model.phase = .active
        model.secondsRemaining = 3_661
        XCTAssertEqual(model.countdown, "1:01:01 remaining")
        model.phase = .recovery
        XCTAssertEqual(model.actionTitle, "Retry Restore Sleep")
    }

    func testCheckingAndAvailableUpdatesDoNotBlockArming() {
        let model = AppModel(defaults: defaults)
        let controller = UpdateController(model: model, canUpdate: { true })
        var canceled = false
        controller.showUserInitiatedUpdateCheck { canceled = true }
        XCTAssertEqual(model.updatePhase, .checking)
        XCTAssertFalse(model.sessionActionDisabled)
        XCTAssertTrue(model.canCancelUpdate)
        controller.cancelUpdate()
        XCTAssertTrue(canceled)
        XCTAssertFalse(model.canCancelUpdate)
        model.updatePhase = .available
        XCTAssertFalse(model.sessionActionDisabled)
    }

    func testInstallationLocksBeforeReplyAndRejectsActiveSession() {
        let model = AppModel(defaults: defaults)
        var idle = false
        let controller = UpdateController(model: model, canUpdate: { idle })
        var replies = 0
        controller.showReady { choice in
            XCTAssertEqual(choice, .install)
            XCTAssertTrue(model.updateBlocksArming)
            replies += 1
        }
        controller.installUpdate()
        XCTAssertEqual(replies, 0)
        XCTAssertTrue(model.canInstallUpdate)
        idle = true
        controller.installUpdate()
        controller.installUpdate()
        XCTAssertEqual(replies, 1, "Consume each Sparkle reply only once")
        XCTAssertEqual(model.updatePhase, .installing)
    }

    func testSafetyActionsRemainEnabledDuringUpdate() {
        let model = AppModel(defaults: defaults)
        for updatePhase in [AppModel.UpdatePhase.downloading, .extracting, .ready, .installing] {
            model.updatePhase = updatePhase
            model.phase = .idle
            XCTAssertTrue(model.sessionActionDisabled)
            for phase in [AppModel.Phase.armed, .active, .recovery] {
                model.phase = phase
                XCTAssertFalse(model.sessionActionDisabled)
            }
        }
    }

    func testCancellationUnlocksOnCompletionWithoutReopeningPopover() {
        let model = AppModel(defaults: defaults)
        let controller = UpdateController(model: model, canUpdate: { true })
        var canceled = false
        controller.showDownloadInitiated { canceled = true }
        controller.cancelUpdate()
        XCTAssertTrue(canceled)
        XCTAssertTrue(model.updateBlocksArming, "Do not unlock until Sparkle has canceled the download")
        let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil).updater
        controller.updater(updater, didFinishUpdateCycleFor: .updates, error: nil)
        XCTAssertFalse(model.sessionActionDisabled)
        XCTAssertFalse(model.canCancelUpdate)
    }

    func testPreparedUpdateCancellationDoesNotLeaveInstallOnQuit() {
        let model = AppModel(defaults: defaults)
        let controller = UpdateController(model: model, canUpdate: { true })
        var choice: SPUUserUpdateChoice?
        controller.showReady { choice = $0 }
        controller.cancelUpdate()
        XCTAssertEqual(choice, .skip, "Dismiss would leave the prepared installation pending on quit")
    }

    func testNetworkFailureAcknowledgesImmediatelyAndClearsActions() {
        let model = AppModel(defaults: defaults)
        let controller = UpdateController(model: model, canUpdate: { true })
        controller.showDownloadInitiated { XCTFail("Stale cancellation callback") }
        var acknowledged = false
        controller.showUpdaterError(URLError(.timedOut)) { acknowledged = true }
        XCTAssertTrue(acknowledged)
        XCTAssertEqual(model.updatePhase, .failed)
        XCTAssertFalse(model.sessionActionDisabled)
        XCTAssertFalse(model.canCancelUpdate)
        XCTAssertFalse(model.canInstallUpdate)
        controller.cancelUpdate()
    }

    func testDownloadProgressHandlesMissingAndInaccurateLength() {
        let model = AppModel(defaults: defaults)
        let controller = UpdateController(model: model, canUpdate: { true })
        controller.showDownloadInitiated {}
        controller.showDownloadDidReceiveData(ofLength: 25)
        XCTAssertNil(model.updateProgress)
        controller.showDownloadDidReceiveExpectedContentLength(100)
        XCTAssertEqual(model.updateProgress, 0.25)
        controller.showDownloadDidReceiveData(ofLength: 100)
        XCTAssertEqual(model.updateProgress, 1)
        controller.showDownloadDidStartExtractingUpdate()
        XCTAssertFalse(model.canCancelUpdate)
        XCTAssertNil(model.updateProgress)
    }
}
