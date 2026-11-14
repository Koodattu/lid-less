import SwiftUI
import LidLessCore

struct PopoverView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var showPreferences = false
    @State private var showAbout = false
    private let buttonAccent = Color(red: 0.11, green: 0.43, blue: 0.34)
    private var accent: Color {
        colorScheme == .dark ? Color(red: 0.45, green: 0.82, blue: 0.70) : buttonAccent
    }

    init(model: AppModel, showPreferences: Bool = false, showAbout: Bool = false) {
        self.model = model
        _showPreferences = State(initialValue: showPreferences)
        _showAbout = State(initialValue: showAbout)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 18) {
                    if showPreferences {
                        preferences
                    } else if showAbout {
                        about
                    } else {
                        if model.showWelcome { welcome }
                        hero
                        if let error = model.powerError { errorMessage(error) }
                        durations
                        primaryAction
                        Text(model.gestureDescription)
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        powerSummary
                    }
                }
                .padding(.horizontal, 22).padding(.bottom, 18)
            }
            footer
        }
        .frame(width: 356, height: showPreferences || showAbout ? 460 : (model.showWelcome || model.powerError != nil ? 600 : 480))
        .background(reduceTransparency ? Color(nsColor: .windowBackgroundColor) : Color.clear)
        .tint(accent)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: model.phase)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showPreferences)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.duration)
    }

    private var header: some View {
        HStack {
            Text(showPreferences ? "Preferences" : (showAbout ? "About Lid Less" : "Lid Less")).font(.system(size: 14, weight: .semibold))
            Spacer()
            if !showPreferences && !showAbout { Text(phaseLabel).font(.caption).foregroundStyle(.secondary) }
            Button {
                if showPreferences || showAbout { showPreferences = false; showAbout = false }
                else { showPreferences = true }
            } label: {
                Image(systemName: showPreferences || showAbout ? "xmark" : "slider.horizontal.3").frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless).accessibilityLabel(showPreferences || showAbout ? "Back to session" : "Preferences")
            .keyboardShortcut(",", modifiers: .command)
            .help(showPreferences || showAbout ? "Back to session" : "Preferences")
        }.padding(.horizontal, 22).padding(.vertical, 16)
    }

    private var phaseLabel: String {
        switch model.phase {
        case .idle: return "Normal sleep"
        case .armed: return "Armed"
        case .active: return "Session active"
        case .recovery: return "Needs attention"
        }
    }

    private var hero: some View {
        VStack(spacing: 9) {
            LaptopIllustration(phase: model.phase, reduceMotion: reduceMotion)
                .frame(width: 94, height: 66).padding(.top, 12).padding(.bottom, 5)
                .accessibilityHidden(true)
            Text(model.title).font(.system(size: 23, weight: .semibold, design: .rounded))
                .tracking(-0.5).multilineTextAlignment(.center)
            if model.phase == .armed || model.phase == .active {
                Text(model.countdown).monospacedDigit().font(.callout)
                    .foregroundStyle(model.phase == .armed ? Color.secondary : accent)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.secondsRemaining)
                if model.phase == .active {
                    Text("Lid closed · Keep-awake requested").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(model.phase == .recovery ? "Retry before closing your Mac." : model.message)
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }.frame(maxWidth: .infinity)
    }

    private var durations: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SESSION LIMIT").font(.system(size: 10, weight: .medium)).tracking(1).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(SessionSettings.durations, id: \.self) { duration in
                    Button { model.duration = duration } label: {
                        Text(AppModel.durationLabel(duration)).font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(model.duration == duration ? accent.opacity(0.18) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(model.duration == duration ? accent.opacity(0.7) : .clear))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(AppModel.durationLabel(duration)) session limit")
                    .accessibilityAddTraits(model.duration == duration ? .isSelected : [])
                }
            }.disabled(model.phase != .idle || model.isUpdating)
        }
    }

    @ViewBuilder private var primaryAction: some View {
        if #available(macOS 26, *), !reduceTransparency {
            actionButton.buttonStyle(.glassProminent)
        } else {
            actionButton.buttonStyle(.borderedProminent)
        }
    }

    private var actionButton: some View {
        Button(action: model.toggleSession) {
            Label(model.actionTitle, systemImage: model.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(controlActiveState == .inactive ? Color.primary : Color.white)
                .frame(maxWidth: .infinity).padding(.vertical, 5)
        }
        .controlSize(.large)
        .tint(buttonAccent)
        .keyboardShortcut(.return, modifiers: [])
        .disabled(model.isUpdating)
    }

    private var powerSummary: some View {
        VStack(spacing: 9) {
            Divider()
            HStack { Label("Power", systemImage: "battery.75percent"); Spacer(); Text(model.powerDescription) }
            HStack { Text("Automatically stops"); Spacer(); Text("On reopen or at \(model.batteryFloor)%") }
        }.font(.caption).foregroundStyle(.secondary)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("A little freedom for your lid.", systemImage: "sparkles").font(.callout.weight(.medium))
            Text("Choose a duration, arm, then close within 60 seconds. Reopen to restore normal sleep.")
            Text("Keep your Mac on a ventilated surface. Screen-lock settings stay unchanged.")
                .foregroundStyle(.secondary)
            Button("Got it") { model.dismissWelcome() }.buttonStyle(.bordered)
        }
        .font(.caption).padding(12)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 12) {
            preferenceToggle("Launch at Login", isOn: Binding(get: { model.loginStatus == .enabled }, set: { _ in model.changeLogin() }))
                .disabled(model.loginStatus == .notFound)
            if model.loginStatus == .requiresApproval {
                HStack {
                    Button("Approve in Login Settings…", action: model.openLoginSettings)
                    Button("Cancel", action: model.changeLogin)
                }.font(.caption)
            }
            if model.loginStatus == .notFound { Text("Move Lid Less to Applications to enable login startup.").foregroundStyle(.secondary) }
            preferenceToggle("Option-close gesture", isOn: $model.gestureEnabled)
            preferenceToggle("Confirmation sound", isOn: $model.soundEnabled)
            Picker("Stop on battery at", selection: $model.batteryFloor) {
                ForEach(SessionSettings.batteryFloors, id: \.self) { Text("\($0)%").tag($0) }
            }.disabled(model.phase != .idle)
            Divider()
            preferenceToggle("Check for updates automatically", isOn: Binding(get: { model.automaticUpdates }, set: model.changeAutomaticUpdates))
            Text("Updates ask before installing. Active sessions are never interrupted.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Show quick start") { model.showWelcome = true; showPreferences = false }
            if let error = model.preferenceError { errorMessage(error) }
        }.font(.callout).toggleStyle(.switch).controlSize(.small)
    }

    private func preferenceToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Text(label).frame(maxWidth: .infinity, alignment: .leading) }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable().frame(width: 64, height: 64).accessibilityHidden(true)
            Text("Lid Less \(model.version)").font(.headline)
            Text("Free, open source, and made for the menu bar. Experimental closed-lid support; behavior varies by Mac and macOS version.")
            HStack {
                Link("Source & releases", destination: URL(string: "https://github.com/Koodattu/lid-less")!)
                Spacer()
                Button("Copy diagnostics", action: model.copyDiagnostics)
            }
            Text("Apache 2.0 · Updates by Sparkle (MIT)").foregroundStyle(.secondary)
        }.font(.caption)
    }

    private func errorMessage(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.caption).foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10).background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let status = model.updateStatus { Text(status).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            HStack {
                Button("About") { showAbout.toggle(); showPreferences = false }
                Spacer()
                Button("Check for Updates…", action: model.checkForUpdates)
                    .disabled(!model.canCheckForUpdates || model.phase != .idle)
                Spacer()
                Button("Quit", action: model.quit).keyboardShortcut("q")
            }.font(.caption).buttonStyle(.borderless)
        }
        .padding(.horizontal, 22).padding(.vertical, 12)
        .background(Color.primary.opacity(0.035))
    }
}

private struct LaptopIllustration: View {
    let phase: AppModel.Phase
    let reduceMotion: Bool
    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [.mint.opacity(0.45), .teal.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.8), lineWidth: 3))
                .frame(width: 75, height: 50).padding(.bottom, 6)
                .rotation3DEffect(.degrees(phase == .active ? 75 : (phase == .armed ? 24 : 0)), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.35)
            Capsule().fill(.primary.opacity(0.8)).frame(height: 4)
        }.animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: phase)
    }
}
