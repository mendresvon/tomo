import Foundation

public enum Phase: String, CaseIterable, Sendable {
    case focus, shortBreak, longBreak

    public var isBreak: Bool { self != .focus }

    public var title: String {
        switch self {
        case .focus: return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }
}

public enum RunState: Sendable {
    case idle, running, paused
}

public struct TimerConfig: Equatable, Sendable {
    public var focus: TimeInterval
    public var shortBreak: TimeInterval
    public var longBreak: TimeInterval
    public var roundsBeforeLongBreak: Int
    /// Start the next phase at once when a phase ends, instead of waiting for a click.
    public var autoStartNext: Bool

    public init(
        focus: TimeInterval = 25 * 60,
        shortBreak: TimeInterval = 5 * 60,
        longBreak: TimeInterval = 15 * 60,
        roundsBeforeLongBreak: Int = 4,
        autoStartNext: Bool = false
    ) {
        self.focus = focus
        self.shortBreak = shortBreak
        self.longBreak = longBreak
        self.roundsBeforeLongBreak = max(1, roundsBeforeLongBreak)
        self.autoStartNext = autoStartNext
    }

    public func duration(for phase: Phase) -> TimeInterval {
        switch phase {
        case .focus: return focus
        case .shortBreak: return shortBreak
        case .longBreak: return longBreak
        }
    }
}

/// Pomodoro state machine.
///
/// Time left is always computed from a fixed end date, not by counting ticks.
/// This keeps it correct after the Mac sleeps or the app is busy.
public final class TimerEngine {
    public private(set) var phase: Phase = .focus { didSet { changed() } }
    public private(set) var state: RunState = .idle { didSet { changed() } }
    public private(set) var remaining: TimeInterval { didSet { if remaining != oldValue { changed() } } }
    /// Finished (not skipped) focus rounds since the last reset.
    public private(set) var completedFocusRounds = 0 { didSet { changed() } }

    /// Called after any value above changes. Several changes in a row call it several times.
    public var onChange: (() -> Void)?

    public var config: TimerConfig {
        didSet {
            if state == .idle { remaining = config.duration(for: phase) }
        }
    }

    /// Called when a phase runs out. Arguments: the phase that ended, the next phase.
    public var onPhaseEnded: ((Phase, Phase) -> Void)?

    private let now: () -> Date
    private var endDate: Date?

    /// When the running phase ends, or nil when the timer is not running.
    public var endsAt: Date? { endDate }

    public init(config: TimerConfig = TimerConfig(), now: @escaping () -> Date = Date.init) {
        self.config = config
        self.now = now
        self.remaining = config.duration(for: .focus)
    }

    public var duration: TimeInterval { config.duration(for: phase) }

    /// 0 at the start of a phase, 1 at the end.
    public var progress: Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, 1 - remaining / duration))
    }

    /// The round that is in progress or next, from 1 to `roundsBeforeLongBreak`.
    public var currentRound: Int {
        let rounds = config.roundsBeforeLongBreak
        if phase == .longBreak { return rounds }
        if phase == .shortBreak { return max(1, completedFocusRounds % rounds) }
        return completedFocusRounds % rounds + 1
    }

    public func start() {
        guard state != .running else { return }
        endDate = now().addingTimeInterval(remaining)
        state = .running
    }

    public func pause() {
        guard state == .running, let endDate else { return }
        remaining = max(0, endDate.timeIntervalSince(now()))
        self.endDate = nil
        state = .paused
    }

    public func toggle() {
        state == .running ? pause() : start()
    }

    /// Go to the next phase now. A skipped focus round does not count as finished.
    public func skip() {
        advance(finished: false)
    }

    public func reset() {
        endDate = nil
        phase = .focus
        state = .idle
        completedFocusRounds = 0
        remaining = config.duration(for: .focus)
    }

    /// Update the time left. Call this when the shown time can change (once a second
    /// while it is visible) and at the end date, so the phase ends on time.
    public func tick() {
        guard state == .running, let endDate else { return }
        remaining = max(0, endDate.timeIntervalSince(now()))
        if remaining <= 0 { advance(finished: true) }
    }

    private func advance(finished: Bool) {
        let ended = phase
        let next: Phase
        if ended == .focus {
            if finished { completedFocusRounds += 1 }
            let longBreakDue = finished && completedFocusRounds % config.roundsBeforeLongBreak == 0
            next = longBreakDue ? .longBreak : .shortBreak
        } else {
            next = .focus
        }

        let keepRunning = finished ? config.autoStartNext : state == .running
        phase = next
        remaining = config.duration(for: next)
        endDate = nil
        state = .idle
        if keepRunning { start() }

        if finished { onPhaseEnded?(ended, next) }
    }

    private func changed() {
        onChange?()
    }
}
