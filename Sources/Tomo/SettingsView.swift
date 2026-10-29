import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var loginItem: LoginItem
    @ObservedObject var shortcuts: ShortcutStore

    var body: some View {
        Form {
            Section("Timer") {
                Stepper("Focus: \(preferences.focusMinutes) min", value: $preferences.focusMinutes, in: 1...120)
                Stepper("Short break: \(preferences.shortBreakMinutes) min", value: $preferences.shortBreakMinutes, in: 1...60)
                Stepper("Long break: \(preferences.longBreakMinutes) min", value: $preferences.longBreakMinutes, in: 1...90)
                Stepper("Rounds before long break: \(preferences.roundsBeforeLongBreak)", value: $preferences.roundsBeforeLongBreak, in: 1...12)
                Toggle("Start the next phase automatically", isOn: $preferences.autoStartNext)
            }

            Section("Alerts") {
                Toggle("Play a sound when a phase ends", isOn: $preferences.soundOn)
                Toggle("Show a notification when a phase ends", isOn: $preferences.notificationsOn)
            }

            Section("Tomo") {
                Picker("Size", selection: $preferences.petSize) {
                    ForEach(PetSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Open Tomo when you log in", isOn: Binding(get: { loginItem.enabled }, set: { loginItem.set($0) }))
                if let loginError = loginItem.error {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                ForEach(Shortcut.allCases) { shortcut in
                    LabeledContent(shortcut.title) {
                        Button {
                            shortcuts.startRecording(shortcut)
                        } label: {
                            Text(shortcuts.recording == shortcut ? "Press keys…" : shortcuts.combo(for: shortcut).label)
                                .font(.body.monospaced())
                                .frame(minWidth: 90)
                        }
                        .buttonStyle(.bordered)
                        .tint(shortcuts.recording == shortcut ? .accentColor : nil)
                    }
                }
                if let message = shortcuts.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                Button("Reset to Defaults") { shortcuts.resetToDefaults() }
            } header: {
                Text("Keyboard shortcuts (work in any app)")
            } footer: {
                Text("Click a shortcut, then press the new keys. Use at least one of ⌘, ⌃, or ⌥.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize()
    }
}

/// Opens Tomo at login with the system login items service.
final class LoginItem: ObservableObject {
    @Published private(set) var enabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var error: String?

    func set(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            error = nil
        } catch {
            self.error = "Could not change this: \(error.localizedDescription)"
        }
        enabled = SMAppService.mainApp.status == .enabled
    }
}
