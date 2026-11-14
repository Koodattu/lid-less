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

    func testUpdateCheckRejectsActiveSessionBeforeLockingUI() {
        let model = AppModel(defaults: defaults)
        var idle = false
        let controller = UpdateController(model: model, canUpdate: { idle })
        let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil).updater
        XCTAssertThrowsError(try controller.updater(updater, mayPerform: .updates))
        XCTAssertFalse(model.isUpdating)
        idle = true
        XCTAssertNoThrow(try controller.updater(updater, mayPerform: .updates))
        XCTAssertTrue(model.isUpdating, "Arming must be blocked synchronously, before the download starts")
        controller.updater(updater, didFinishUpdateCycleFor: .updates, error: nil)
        XCTAssertFalse(model.isUpdating, "Completing or canceling a check must make arming available again")
    }
}
