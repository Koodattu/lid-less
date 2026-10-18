import XCTest
@testable import LidLessCore

final class FakePower: SleepOverride {
    var starts = 0
    var stops = 0
    var refreshes = 0
    var failStart = false
    var failStop = false
    var failRefresh = false
    func start() throws {
        starts += 1
        if failStart { throw SessionError("start failed") }
    }
    func stop() throws {
        stops += 1
        if failStop { throw SessionError("stop failed") }
    }
    func refresh() throws {
        refreshes += 1
        if failRefresh { throw SessionError("refresh failed") }
    }
}

final class SessionControllerTests: XCTestCase {
    private func arm(_ controller: SessionController) throws {
        try controller.arm(now: 0, lidClosed: false, batteryPercent: 80, onAC: true)
    }

    private func tick(_ controller: SessionController, now: Double = 1, closed: Bool? = false,
                      angle: Double? = nil, option: Bool = false, battery: Int = 80,
                      ac: Bool = true, critical: Bool = false) throws {
        try controller.tick(now: now, lidClosed: closed, angle: angle, optionHeld: option,
                            batteryPercent: battery, onAC: ac, thermalCritical: critical)
    }

    func testCloseAndReopenRestoresExactlyOnce() throws {
        let power = FakePower()
        let controller = SessionController(power: power)
        try arm(controller)
        try tick(controller, closed: true)
        XCTAssertEqual(controller.state, .active(until: 28_801))
        try tick(controller, now: 2)
        try controller.stop()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(power.starts, 1)
        XCTAssertEqual(power.stops, 1)
    }

    func testUnclosedArmingExpires() throws {
        let power = FakePower()
        let controller = SessionController(power: power)
        try arm(controller)
        try tick(controller, now: 60)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(power.stops, 1)
    }

    func testSessionTimeLimitRestores() throws {
        let power = FakePower()
        let controller = SessionController(power: power)
        try arm(controller)
        try tick(controller, closed: true)
        try tick(controller, now: 28_801, closed: true)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(power.stops, 1)
    }

    func testLowBatteryOnlyStopsOnBatteryPower() throws {
        let power = FakePower()
        let controller = SessionController(power: power)
        try arm(controller)
        try tick(controller, closed: true, battery: 15)
        XCTAssertEqual(power.stops, 0)
        try tick(controller, closed: true, battery: 15, ac: false)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(power.stops, 1)
    }

    func testPowerTransitionRefreshesOnce() throws {
        let power = FakePower()
        let controller = SessionController(power: power)
        try arm(controller)
        try tick(controller, closed: true, ac: false)
        try tick(controller, closed: true, ac: false)
        XCTAssertEqual(power.refreshes, 1)
        XCTAssertEqual(power.stops, 0)
    }

    func testRefreshFailureDisarms() throws {
        let power = FakePower()
        power.failRefresh = true
        let controller = SessionController(power: power)
        try arm(controller)
        XCTAssertThrowsError(try tick(controller, closed: true, ac: false))
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(power.stops, 1)
    }

    func testPartialStartRollsBack() {
        let power = FakePower()
        power.failStart = true
        let controller = SessionController(power: power)
        XCTAssertThrowsError(try arm(controller))
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(power.stops, 1)
    }

    func testRestorationFailureRemainsVisibleAndCanBeRetried() throws {
        let power = FakePower()
        let controller = SessionController(power: power)
        try arm(controller)
        power.failStop = true
        XCTAssertThrowsError(try controller.stop())
        XCTAssertEqual(controller.state, .recoveryRequired)
        try arm(controller)
        XCTAssertEqual(power.starts, 1)
        power.failStop = false
        try controller.stop()
        XCTAssertEqual(controller.state, .idle)
    }

    func testUnsafeArmingDoesNotTouchPower() {
        let power = FakePower()
        let controller = SessionController(power: power)
        for closed: Bool? in [true, nil] {
            XCTAssertThrowsError(try controller.arm(now: 0, lidClosed: closed, batteryPercent: 80, onAC: true))
        }
        XCTAssertThrowsError(try controller.arm(now: 0, lidClosed: false, batteryPercent: 15, onAC: false))
        XCTAssertEqual(power.starts, 0)
    }

    func testUnknownLidAndCriticalTemperatureStopSession() throws {
        for critical in [false, true] {
            let power = FakePower()
            let controller = SessionController(power: power)
            try arm(controller)
            try tick(controller, closed: critical ? false : nil, critical: critical)
            XCTAssertEqual(controller.state, .idle)
            XCTAssertEqual(power.stops, 1)
        }
    }

    func testGestureRequiresOptionAndClosingMovement() throws {
        let power = FakePower()
        let controller = SessionController(power: power)
        try tick(controller, angle: 90, option: true)
        try tick(controller, angle: 80, option: true)
        XCTAssertEqual(power.starts, 0)
        try tick(controller, angle: 60, option: false)
        XCTAssertEqual(power.starts, 0)
        try tick(controller, angle: 65, option: true)
        XCTAssertEqual(power.starts, 0)
        try tick(controller, angle: 60, option: true)
        XCTAssertEqual(power.starts, 1)
        try controller.stop()
        try tick(controller, angle: 50, option: true)
        XCTAssertEqual(power.starts, 1, "Disarming while Option is held must not immediately rearm")
    }

    func testMissingSensorNeverAutomaticallyArms() throws {
        let power = FakePower()
        let controller = SessionController(power: power)
        try tick(controller, option: true)
        try tick(controller, option: true)
        XCTAssertEqual(power.starts, 0)
        try arm(controller)
        XCTAssertEqual(power.starts, 1)
    }

    func testSensorReportValidation() {
        XCTAssertEqual(LidAngleSensor.decode([1, 90, 0]), 90)
        XCTAssertNil(LidAngleSensor.decode([1, 90]))
        XCTAssertNil(LidAngleSensor.decode([2, 90, 0]))
        XCTAssertNil(LidAngleSensor.decode([1, 0, 1]))
    }
}
