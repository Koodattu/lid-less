import AppKit
import Combine
import LidLessCore
import ServiceManagement

/// Presentation state only. Power requests stay in SessionController and its worker.
final class AppModel: ObservableObject {
    enum Phase: String, CaseIterable { case idle, armed, active, recovery }
    enum UpdatePhase { case idle, checking, available, downloading, extracting, ready, installing, finished, failed }
    @Published var phase: Phase = .idle
    @Published var secondsRemaining = 0
    @Published var message = "Normal lid-close sleep"
    @Published var powerError: String?
    @Published var preferenceError: String?
    @Published var sensorAvailable = false
    @Published var gesturePaused = false
    @Published var batteryPercent: Int?
    @Published var onAC: Bool?
    @Published var loginStatus: SMAppService.Status = .notRegistered
    @Published var canCheckForUpdates = true
    @Published var automaticUpdates = false
    @Published var updateStatus: String?
    @Published var updatePhase: UpdatePhase = .idle
    @Published var showUpdates = false
    @Published var updateVersion = ""
    @Published var updateProgress: Double?
    @Published var canCancelUpdate = false
    @Published var canInstallUpdate = false
    @Published var duration: Double { didSet { defaults.set(duration, forKey: "sessionDuration") } }
    @Published var batteryFloor: Int { didSet { defaults.set(batteryFloor, forKey: "batteryFloor") } }
    @Published var gestureEnabled: Bool { didSet { defaults.set(gestureEnabled, forKey: "gestureEnabled") } }
    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: "soundEnabled") } }
    @Published var showWelcome: Bool
    private let defaults: UserDefaults

    var toggleSession: () -> Void = {}
    var changeLogin: () -> Void = {}
    var openLoginSettings: () -> Void = {}
    var checkForUpdates: () -> Void = {}
    var installUpdate: () -> Void = {}
    var cancelUpdate: () -> Void = {}
    var changeAutomaticUpdates: (Bool) -> Void = { _ in }
    var quit: () -> Void = {}
    var copyDiagnostics: () -> Void = {}

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let settings = SessionSettings(duration: defaults.double(forKey: "sessionDuration"),
                                       batteryFloor: defaults.integer(forKey: "batteryFloor"))
        duration = settings.duration
        batteryFloor = settings.batteryFloor
        gestureEnabled = defaults.object(forKey: "gestureEnabled") as? Bool ?? true
        soundEnabled = defaults.bool(forKey: "soundEnabled")
        showWelcome = !defaults.bool(forKey: "hasSeenWelcome")
    }

    func dismissWelcome() {
        defaults.set(true, forKey: "hasSeenWelcome")
        showWelcome = false
    }

    var settings: SessionSettings { SessionSettings(duration: duration, batteryFloor: batteryFloor) }
    var updateBlocksArming: Bool {
        [.downloading, .extracting, .ready, .installing].contains(updatePhase)
    }
    var sessionActionDisabled: Bool { phase == .idle && updateBlocksArming }
    var updateTitle: String {
        switch updatePhase {
        case .idle: return "Keep Lid Less up to date."
        case .checking: return "Checking for updates…"
        case .available: return "Lid Less \(updateVersion) is available."
        case .downloading: return "Downloading update…"
        case .extracting: return "Preparing update…"
        case .ready: return "Ready to restart."
        case .installing: return "Restarting Lid Less…"
        case .finished: return "Check complete."
        case .failed: return "Update couldn’t complete."
        }
    }
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development" }
    var title: String {
        switch phase {
        case .idle: return powerError == nil ? "Close with confidence." : "Let’s try again."
        case .armed: return "Ready when you are."
        case .active: return "Keeping work going."
        case .recovery: return "Let’s restore sleep."
        }
    }
    var actionTitle: String {
        switch phase {
        case .idle: return "Arm for Next Close"
        case .armed: return "Cancel Arming"
        case .active: return "End Session"
        case .recovery: return "Retry Restore Sleep"
        }
    }
    var symbol: String {
        switch phase {
        case .idle: return "laptopcomputer"
        case .armed: return "clock"
        case .active: return "bolt.fill"
        case .recovery: return "exclamationmark.triangle.fill"
        }
    }
    var countdown: String {
        let seconds = max(0, secondsRemaining)
        if phase == .armed { return "Close within \(seconds)s" }
        return String(format: "%d:%02d:%02d remaining", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }
    var powerDescription: String {
        let charge = batteryPercent.map { "\($0)%" } ?? "Unavailable"
        return charge + (onAC.map { $0 ? " · Plugged in" : " · Battery" } ?? "")
    }
    var gestureDescription: String {
        if gesturePaused { return "Option-close paused. Arm manually to retry." }
        if !sensorAvailable { return "Lid sensor unavailable. Use the button to arm." }
        return gestureEnabled ? "Or hold ⌥ while lowering the lid" : "Option-close is off"
    }
    static func durationLabel(_ seconds: Double) -> String {
        seconds == 1800 ? "30 min" : "\(Int(seconds / 3600)) hr"
    }
}
