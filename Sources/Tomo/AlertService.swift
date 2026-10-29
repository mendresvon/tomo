import AppKit
import TomoCore
import UserNotifications

/// Plays a sound and shows a macOS notification when a phase ends.
final class AlertService: NSObject, UNUserNotificationCenterDelegate {
    /// Notifications only work when Tomo runs as a bundled .app.
    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    func setUp() {
        guard canNotify else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func phaseEnded(_ ended: Phase, next: Phase, preferences: Preferences) {
        if preferences.soundOn {
            NSSound(named: ended == .focus ? "Glass" : "Hero")?.play()
        }
        guard preferences.notificationsOn, canNotify else { return }

        let content = UNMutableNotificationContent()
        switch next {
        case .shortBreak:
            content.title = "Focus done!"
            content.body = "Nice work. Take a \(preferences.shortBreakMinutes) minute break."
        case .longBreak:
            content.title = "\(preferences.roundsBeforeLongBreak) rounds done!"
            content.body = "You earned a \(preferences.longBreakMinutes) minute break."
        case .focus:
            content.title = "Break is over"
            content.body = "Tomo is ready to focus again."
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // Show the banner even when Tomo counts as the active app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}
