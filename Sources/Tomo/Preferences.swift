import Foundation
import TomoCore

enum PetSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Screen points per sprite pixel.
    var pixelSize: CGFloat {
        switch self {
        case .small: return 4
        case .medium: return 5
        case .large: return 6
        }
    }
}

/// User settings, saved in UserDefaults.
final class Preferences: ObservableObject {
    private let defaults = UserDefaults.standard

    /// Called after any setting changes.
    var onChange: (() -> Void)?

    @Published var focusMinutes: Int { didSet { save(focusMinutes, "focusMinutes") } }
    @Published var shortBreakMinutes: Int { didSet { save(shortBreakMinutes, "shortBreakMinutes") } }
    @Published var longBreakMinutes: Int { didSet { save(longBreakMinutes, "longBreakMinutes") } }
    @Published var roundsBeforeLongBreak: Int { didSet { save(roundsBeforeLongBreak, "roundsBeforeLongBreak") } }
    @Published var autoStartNext: Bool { didSet { save(autoStartNext, "autoStartNext") } }
    @Published var soundOn: Bool { didSet { save(soundOn, "soundOn") } }
    @Published var notificationsOn: Bool { didSet { save(notificationsOn, "notificationsOn") } }
    @Published var petSize: PetSize { didSet { save(petSize.rawValue, "petSize") } }

    init() {
        defaults.register(defaults: [
            "focusMinutes": 25,
            "shortBreakMinutes": 5,
            "longBreakMinutes": 15,
            "roundsBeforeLongBreak": 4,
            "autoStartNext": false,
            "soundOn": true,
            "notificationsOn": true,
            "petSize": PetSize.medium.rawValue,
        ])
        focusMinutes = defaults.integer(forKey: "focusMinutes")
        shortBreakMinutes = defaults.integer(forKey: "shortBreakMinutes")
        longBreakMinutes = defaults.integer(forKey: "longBreakMinutes")
        roundsBeforeLongBreak = defaults.integer(forKey: "roundsBeforeLongBreak")
        autoStartNext = defaults.bool(forKey: "autoStartNext")
        soundOn = defaults.bool(forKey: "soundOn")
        notificationsOn = defaults.bool(forKey: "notificationsOn")
        petSize = PetSize(rawValue: defaults.string(forKey: "petSize") ?? "") ?? .medium
    }

    var timerConfig: TimerConfig {
        TimerConfig(
            focus: TimeInterval(focusMinutes * 60),
            shortBreak: TimeInterval(shortBreakMinutes * 60),
            longBreak: TimeInterval(longBreakMinutes * 60),
            roundsBeforeLongBreak: roundsBeforeLongBreak,
            autoStartNext: autoStartNext
        )
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        onChange?()
    }
}
