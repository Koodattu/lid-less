import Foundation

public protocol SleepOverride: AnyObject {
    func start() throws
    func refresh() throws
    func stop() throws
}

/// Policy is separate from IOKit so lifecycle and failure paths can be tested safely.
public final class SessionController {
    public enum State: Equatable {
        case idle
        case armed(until: TimeInterval)
        case active(until: TimeInterval)
        case recoveryRequired
    }

    public private(set) var state: State = .idle
    public private(set) var message = "Normal lid-close sleep"
    public var settings = SessionSettings()
    public private(set) var sessionSettings = SessionSettings()
    private let power: SleepOverride
    private var previousAngle: Double?
    private var gestureReady = true
    private var previousAC: Bool?

    public init(power: SleepOverride) { self.power = power }

    public func arm(now: TimeInterval, lidClosed: Bool?, batteryPercent: Int?, onAC: Bool?, thermalCritical: Bool = false) throws {
        guard state == .idle else { return }
        guard lidClosed == false else { throw SessionError("Open the lid before arming.") }
        guard !thermalCritical else { throw SessionError("Let your Mac cool down before arming.") }
        guard !(onAC == false && (batteryPercent ?? 100) <= settings.batteryFloor) else {
            throw SessionError("Battery is at or below \(settings.batteryFloor)%. Connect power before arming.")
        }
        sessionSettings = settings
        // A failed start can still leave a partially applied override.
        state = .recoveryRequired
        do {
            try power.start()
            state = .armed(until: now + 60)
            message = "Armed — close the lid within 60 seconds"
            previousAC = onAC
        } catch {
            let startError = error
            do { try stop(reason: "Could not arm") }
            catch { throw SessionError("\(startError.localizedDescription) Restoration also failed: \(error.localizedDescription)") }
            throw startError
        }
    }

    public func stop(reason: String = "Normal lid-close sleep") throws {
        guard state != .idle else { return }
        state = .recoveryRequired
        message = "Restoration required — retry Disarm"
        gestureReady = false
        try power.stop()
        state = .idle
        message = reason
    }

    public func tick(now: TimeInterval, lidClosed: Bool?, angle: Double?, optionHeld: Bool,
                     batteryPercent: Int?, onAC: Bool?, thermalCritical: Bool = false) throws {
        defer { previousAngle = angle }
        if !optionHeld { gestureReady = true }

        if state == .idle {
            // Arm well before the hardware's closed-lid notification can trigger sleep.
            if gestureReady, optionHeld, lidClosed == false,
               let angle, let previousAngle, angle <= 70, angle >= 5, previousAngle - angle >= 1 {
                gestureReady = false
                try arm(now: now, lidClosed: lidClosed, batteryPercent: batteryPercent, onAC: onAC, thermalCritical: thermalCritical)
            }
            return
        }
        guard state != .recoveryRequired else { return }
        if thermalCritical || (onAC == false && (batteryPercent ?? 100) <= sessionSettings.batteryFloor) {
            try stop(reason: thermalCritical ? "Stopped — critical temperature" : "Stopped — battery at \(sessionSettings.batteryFloor)%")
            return
        }
        guard let lidClosed else {
            try stop(reason: "Stopped — lid state unavailable")
            return
        }
        switch state {
        case .armed(let deadline):
            if now >= deadline { try stop(reason: "Arming expired"); return }
            if lidClosed {
                state = .active(until: now + sessionSettings.duration)
                message = "Lid closed — keep-awake requested"
            }
        case .active(let deadline):
            if !lidClosed { try stop(); return }
            if now >= deadline { try stop(reason: "Stopped — session time limit"); return }
        default: break
        }
        if let onAC, onAC != previousAC {
            do { try power.refresh() }
            catch {
                let refreshError = error
                try stop(reason: "Stopped — power transition failed")
                throw refreshError
            }
            previousAC = onAC
        }
    }
}

public struct SessionError: LocalizedError {
    public let errorDescription: String?
    public init(_ message: String) { errorDescription = message }
}
