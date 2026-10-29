import SwiftUI
import TomoCore

/// Shared state for the pet view: the timer, the settings, and window actions.
final class PetModel: ObservableObject {
    let engine: TimerEngine
    let preferences: Preferences
    let shortcuts: ShortcutStore
    /// Tomo celebrates until this time after a phase ends.
    @Published var celebrateUntil: Date?
    // View state lives here because the Command Line Tools cannot expand the @State macro.
    @Published var squash = false
    @Published var hovering = false

    var openSettings: () -> Void = {}
    var hidePet: () -> Void = {}
    var dragChanged: () -> Bool = { false }
    var dragEnded: () -> Bool = { false }

    init(engine: TimerEngine, preferences: Preferences, shortcuts: ShortcutStore) {
        self.engine = engine
        self.preferences = preferences
        self.shortcuts = shortcuts
    }

    func celebrate() {
        celebrateUntil = Date().addingTimeInterval(4)
    }
}

struct PetView: View {
    @ObservedObject var model: PetModel
    @ObservedObject var engine: TimerEngine
    @ObservedObject var preferences: Preferences

    init(model: PetModel) {
        self.model = model
        self.engine = model.engine
        self.preferences = model.preferences
    }

    var body: some View {
        let pixel = preferences.petSize.pixelSize
        HStack(spacing: pixel) {
            // The mood is checked once a second, so the celebration ends on time.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                AnimatedPet(mood: mood(at: context.date), pixelSize: pixel)
            }
            .scaleEffect(x: model.squash ? 1.12 : 1, y: model.squash ? 0.86 : 1, anchor: .bottom)

            TimeBadge(engine: engine, scale: pixel / 5, hovering: model.hovering)
                // Line the badge up with Tomo's body, below the room kept for jumps and Zs.
                .padding(.top, pixel * 4)
        }
        .padding(pixel)
        .contentShape(Rectangle())
        .onHover { model.hovering = $0 }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { _ in _ = model.dragChanged() }
                .onEnded { _ in
                    let moved = model.dragEnded()
                    if !moved { tap() }
                }
        )
        .contextMenu { menu }
        .help("Click: start or pause. Drag: move. Right-click: menu.")
    }

    private func mood(at date: Date) -> Mood {
        if let until = model.celebrateUntil, until > date { return .celebrate }
        switch engine.state {
        case .running: return engine.phase == .focus ? .focus : .rest
        case .paused: return .sleep
        case .idle: return .idle
        }
    }

    private func tap() {
        model.celebrateUntil = nil
        engine.toggle()
        withAnimation(.spring(response: 0.12, dampingFraction: 0.5)) { model.squash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.35)) { model.squash = false }
        }
    }

    @ViewBuilder private var menu: some View {
        Button(engine.state == .running ? "Pause" : engine.state == .paused ? "Resume" : "Start") { engine.toggle() }
        Button("Skip to Next Phase") { engine.skip() }
        Button("Reset") { engine.reset() }
        Divider()
        Button("Settings…") { model.openSettings() }
        Button("Hide Tomo (\(model.shortcuts.combo(for: .showHide).label) to show)") { model.hidePet() }
        Divider()
        Button("Quit Tomo") { NSApp.terminate(nil) }
    }
}

/// Time left, the phase and round, and a blocky progress bar.
private struct TimeBadge: View {
    @ObservedObject var engine: TimerEngine
    let scale: CGFloat
    let hovering: Bool

    private var color: Color {
        switch engine.phase {
        case .focus: return Color(hex: 0xFF5B5B)
        case .shortBreak: return Color(hex: 0x5CC96B)
        case .longBreak: return Color(hex: 0x4D9DE0)
        }
    }

    private var timeText: String {
        let total = Int(engine.remaining.rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private var caption: String {
        if hovering && engine.state == .idle { return "click to start" }
        if engine.phase == .focus {
            return "FOCUS \(engine.currentRound)/\(engine.config.roundsBeforeLongBreak)"
        }
        return engine.phase == .longBreak ? "LONG BREAK" : "BREAK"
    }

    var body: some View {
        VStack(spacing: 3 * scale) {
            Text(timeText)
                .font(.system(size: 18 * scale, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
            Text(caption)
                .font(.system(size: 8 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
            BlockBar(progress: engine.progress, color: color, scale: scale)
        }
        .padding(.horizontal, 10 * scale)
        .padding(.vertical, 6 * scale)
        .background(
            RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                .fill(Color(hex: 0x2A1620).opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                .strokeBorder(color.opacity(0.9), lineWidth: 2 * scale)
        )
    }
}

/// A progress bar made of square blocks.
private struct BlockBar: View {
    let progress: Double
    let color: Color
    let scale: CGFloat
    private let blocks = 10

    var body: some View {
        let filled = Int((progress * Double(blocks)).rounded(.down))
        HStack(spacing: 2 * scale) {
            ForEach(0..<blocks, id: \.self) { i in
                Rectangle()
                    .fill(i < filled ? color : Color.white.opacity(0.18))
                    .frame(width: 6 * scale, height: 5 * scale)
            }
        }
    }
}
