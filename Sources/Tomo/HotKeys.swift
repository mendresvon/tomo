import AppKit
import Carbon.HIToolbox

/// The actions you can trigger with a global keyboard shortcut.
enum Shortcut: String, CaseIterable {
    case toggle, skip, showHide

    var title: String {
        switch self {
        case .toggle: return "Start or pause"
        case .skip: return "Skip to next phase"
        case .showHide: return "Show or hide Tomo"
        }
    }

    /// Control + Option + P, S, or T.
    var defaultCombo: KeyCombo {
        let modifiers = UInt32(controlKey | optionKey)
        switch self {
        case .toggle: return KeyCombo(keyCode: UInt32(kVK_ANSI_P), modifiers: modifiers, key: "P")
        case .skip: return KeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: modifiers, key: "S")
        case .showHide: return KeyCombo(keyCode: UInt32(kVK_ANSI_T), modifiers: modifiers, key: "T")
        }
    }

    /// Carbon hot key ids must be numbers.
    var hotKeyID: UInt32 { UInt32(Shortcut.allCases.firstIndex(of: self)! + 1) }
}

/// A key plus modifier keys, for example ⌃⌥P.
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    /// Carbon modifier flags (controlKey, optionKey, shiftKey, cmdKey).
    var modifiers: UInt32
    /// The key's name as shown to the user, for example "P" or "Space".
    var key: String

    var label: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + key
    }

    /// Makes a combo from a key press. Returns nil when no Command, Control,
    /// or Option key is held, because a plain key would block normal typing.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        guard modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 else { return nil }

        let code = UInt32(event.keyCode)
        let name = KeyCombo.specialKeyNames[Int(code)]
            ?? event.charactersIgnoringModifiers?.uppercased()
            ?? ""
        guard !name.isEmpty, name != " " else { return nil }
        self.init(keyCode: code, modifiers: modifiers, key: name)
    }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

/// Your chosen shortcuts, saved in UserDefaults, plus the "press new keys" recorder.
final class ShortcutStore {
    private(set) var combos: [Shortcut: KeyCombo] = [:] { didSet { onUpdate?() } }
    /// The shortcut that is waiting for new keys, if any.
    private(set) var recording: Shortcut? { didSet { onUpdate?() } }
    private(set) var message: String? { didSet { onUpdate?() } }

    /// Called whenever the hot keys must be registered again.
    var onChange: (() -> Void)?
    /// Called whenever something shown in Settings changes.
    var onUpdate: (() -> Void)?

    private let defaults = UserDefaults.standard
    private var monitor: Any?

    init() {
        for shortcut in Shortcut.allCases {
            if let data = defaults.data(forKey: key(for: shortcut)),
               let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
                combos[shortcut] = combo
            } else {
                combos[shortcut] = shortcut.defaultCombo
            }
        }
    }

    func combo(for shortcut: Shortcut) -> KeyCombo {
        combos[shortcut] ?? shortcut.defaultCombo
    }

    /// Waits for the next key press in the Settings window and uses it for this shortcut.
    func startRecording(_ shortcut: Shortcut) {
        stopRecording()
        recording = shortcut
        message = "Press the new keys for “\(shortcut.title)”. Press Esc to cancel."
        // Turn the hot keys off, so pressing a current shortcut reaches the recorder.
        HotKeys.shared.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil
        }
    }

    func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording != nil {
            recording = nil
            onChange?()
        }
    }

    func resetToDefaults() {
        stopRecording()
        for shortcut in Shortcut.allCases {
            combos[shortcut] = shortcut.defaultCombo
            defaults.removeObject(forKey: key(for: shortcut))
        }
        message = nil
        onChange?()
    }

    /// Shows a problem found while registering, for example keys another app already uses.
    func report(failed: [Shortcut]) {
        guard !failed.isEmpty else { return }
        let names = failed.map { "\(combo(for: $0).label) (\($0.title))" }.joined(separator: ", ")
        message = "Another app already uses \(names). Pick different keys."
    }

    private func handle(_ event: NSEvent) {
        guard let shortcut = recording else { return }
        if event.keyCode == UInt16(kVK_Escape) {
            message = nil
            stopRecording()
            return
        }
        guard let combo = KeyCombo(event: event) else {
            message = "Hold ⌘, ⌃, or ⌥ together with a key."
            return
        }
        if let other = Shortcut.allCases.first(where: { $0 != shortcut && self.combo(for: $0) == combo }) {
            message = "\(combo.label) is already used for “\(other.title)”."
            return
        }
        combos[shortcut] = combo
        if let data = try? JSONEncoder().encode(combo) {
            defaults.set(data, forKey: key(for: shortcut))
        }
        message = nil
        stopRecording()
    }

    private func key(for shortcut: Shortcut) -> String {
        "shortcut.\(shortcut.rawValue)"
    }
}

/// Registers system-wide hot keys with the Carbon API.
/// This needs no Accessibility permission.
final class HotKeys {
    static let shared = HotKeys()

    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var handlerInstalled = false

    func setAction(for shortcut: Shortcut, _ action: @escaping () -> Void) {
        actions[shortcut.hotKeyID] = action
    }

    /// Replaces all hot keys. Returns the shortcuts that could not be registered,
    /// usually because another app already uses the same keys.
    @discardableResult
    func apply(_ store: ShortcutStore) -> [Shortcut] {
        installHandlerIfNeeded()
        unregisterAll()
        var failed: [Shortcut] = []
        for shortcut in Shortcut.allCases {
            let combo = store.combo(for: shortcut)
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x544F_4D4F), id: shortcut.hotKeyID) // "TOMO"
            let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
            } else {
                failed.append(shortcut)
            }
        }
        return failed
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &id
            )
            DispatchQueue.main.async { HotKeys.shared.actions[id.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
