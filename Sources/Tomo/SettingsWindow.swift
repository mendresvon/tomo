import AppKit
import ServiceManagement

/// The Settings window, built with plain AppKit controls.
/// It is created only when you open it, and released when you close it.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let preferences: Preferences
    private let shortcuts: ShortcutStore
    private let loginItem = LoginItem()

    /// Keeps the closures behind each control alive.
    private var actions: [ControlAction] = []
    private var shortcutButtons: [Shortcut: NSButton] = [:]
    private let shortcutMessage = NSTextField(wrappingLabelWithString: "")
    private let loginError = NSTextField(wrappingLabelWithString: "")

    /// Called after the window closes.
    var onClose: () -> Void = {}

    init(preferences: Preferences, shortcuts: ShortcutStore) {
        self.preferences = preferences
        self.shortcuts = shortcuts
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.title = "Tomo Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = makeContent()
        window.center()
        shortcuts.onUpdate = { [weak self] in self?.refreshShortcuts() }
        refreshShortcuts()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func windowWillClose(_ notification: Notification) {
        shortcuts.stopRecording()
        shortcuts.onUpdate = nil
        onClose()
    }

    // MARK: - Layout

    private func makeContent() -> NSView {
        let p = preferences
        let stack = NSStackView(views: [
            header("Timer"),
            grid([
                stepper("Focus", value: p.focusMinutes, range: 1...120, unit: "min") { p.focusMinutes = $0 },
                stepper("Short break", value: p.shortBreakMinutes, range: 1...60, unit: "min") { p.shortBreakMinutes = $0 },
                stepper("Long break", value: p.longBreakMinutes, range: 1...90, unit: "min") { p.longBreakMinutes = $0 },
                stepper("Rounds before long break", value: p.roundsBeforeLongBreak, range: 1...12, unit: "") { p.roundsBeforeLongBreak = $0 },
            ]),
            checkbox("Start the next phase automatically", on: p.autoStartNext) { p.autoStartNext = $0 },

            header("Alerts"),
            checkbox("Play a sound when a phase ends", on: p.soundOn) { p.soundOn = $0 },
            checkbox("Show a notification when a phase ends", on: p.notificationsOn) { p.notificationsOn = $0 },

            header("Tomo"),
            grid([[label("Size"), sizePicker()]]),
            // One group, so the space before the next section stays when the error is hidden.
            group([loginCheckbox(), loginError]),

            header("Keyboard shortcuts (work in any app)"),
            grid(Shortcut.allCases.map { [label($0.title), shortcutButton($0)] }),
            shortcutMessage,
            button("Reset to Defaults") { [weak self] in self?.shortcuts.resetToDefaults() },
            note("Click a shortcut, then press the new keys. Use at least one of ⌘, ⌃, or ⌥."),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        let views = stack.arrangedSubviews
        for (i, view) in views.enumerated() where view.identifier == Self.headerID {
            stack.setCustomSpacing(6, after: view)
            if i > 0 { stack.setCustomSpacing(20, after: views[i - 1]) }
        }
        for view in [shortcutMessage, loginError] {
            view.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            view.preferredMaxLayoutWidth = 360
        }
        loginError.textColor = .systemRed
        loginError.isHidden = true
        shortcutMessage.textColor = .secondaryLabelColor
        stack.widthAnchor.constraint(equalToConstant: 400).isActive = true
        return stack
    }

    private static let headerID = NSUserInterfaceItemIdentifier("header")

    private func header(_ text: String) -> NSView {
        let field = NSTextField(labelWithString: text)
        field.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        field.identifier = Self.headerID
        return field
    }

    private func label(_ text: String) -> NSTextField { NSTextField(labelWithString: text) }

    private func group(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        return stack
    }

    private func note(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.textColor = .secondaryLabelColor
        field.preferredMaxLayoutWidth = 360
        return field
    }

    private func grid(_ rows: [[NSView]]) -> NSGridView {
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.column(at: 0).width = 170
        grid.rowAlignment = .firstBaseline
        return grid
    }

    // MARK: - Controls

    private func bind(_ control: NSControl, _ run: @escaping (NSControl) -> Void) {
        let action = ControlAction(run)
        actions.append(action)
        control.target = action
        control.action = #selector(ControlAction.fire(_:))
    }

    private func stepper(_ title: String, value: Int, range: ClosedRange<Int>, unit: String, set: @escaping (Int) -> Void) -> [NSView] {
        let text = { (n: Int) in unit.isEmpty ? "\(n)" : "\(n) \(unit)" }
        let shown = NSTextField(labelWithString: text(value))
        shown.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let stepper = NSStepper()
        stepper.minValue = Double(range.lowerBound)
        stepper.maxValue = Double(range.upperBound)
        stepper.integerValue = value
        bind(stepper) { control in
            shown.stringValue = text(control.integerValue)
            set(control.integerValue)
        }
        let row = NSStackView(views: [stepper, shown])
        row.spacing = 6
        return [label(title), row]
    }

    private func checkbox(_ title: String, on: Bool, set: @escaping (Bool) -> Void) -> NSButton {
        let box = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        box.state = on ? .on : .off
        bind(box) { set(($0 as? NSButton)?.state == .on) }
        return box
    }

    private func button(_ title: String, run: @escaping () -> Void) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        bind(button) { _ in run() }
        return button
    }

    private func sizePicker() -> NSSegmentedControl {
        let sizes = PetSize.allCases
        let picker = NSSegmentedControl(labels: sizes.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
        picker.selectedSegment = sizes.firstIndex(of: preferences.petSize) ?? 1
        picker.widthAnchor.constraint(equalToConstant: 176).isActive = true
        bind(picker) { [weak self] control in
            guard let picker = control as? NSSegmentedControl, sizes.indices.contains(picker.selectedSegment) else { return }
            self?.preferences.petSize = sizes[picker.selectedSegment]
        }
        return picker
    }

    private func loginCheckbox() -> NSButton {
        checkbox("Open Tomo when you log in", on: loginItem.enabled) { [weak self] on in
            guard let self else { return }
            loginItem.set(on)
            loginError.stringValue = loginItem.error ?? ""
            loginError.isHidden = loginItem.error == nil
        }
    }

    private func shortcutButton(_ shortcut: Shortcut) -> NSButton {
        let button = button("") { [weak self] in self?.shortcuts.startRecording(shortcut) }
        button.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
        shortcutButtons[shortcut] = button
        return button
    }

    private func refreshShortcuts() {
        for (shortcut, button) in shortcutButtons {
            let recording = shortcuts.recording == shortcut
            button.title = recording ? "Press keys…" : shortcuts.combo(for: shortcut).label
            button.bezelColor = recording ? .controlAccentColor : nil
        }
        shortcutMessage.stringValue = shortcuts.message ?? ""
        shortcutMessage.isHidden = shortcuts.message == nil
    }
}

/// Runs a closure when a control sends its action.
private final class ControlAction: NSObject {
    private let run: (NSControl) -> Void
    init(_ run: @escaping (NSControl) -> Void) { self.run = run }
    @objc func fire(_ sender: NSControl) { run(sender) }
}

/// Opens Tomo at login with the system login items service.
final class LoginItem {
    private(set) var enabled = SMAppService.mainApp.status == .enabled
    private(set) var error: String?

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
