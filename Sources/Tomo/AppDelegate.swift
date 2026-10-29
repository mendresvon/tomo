import AppKit
import Combine
import SwiftUI
import TomoCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
    private lazy var engine = TimerEngine(config: preferences.timerConfig)
    private let shortcuts = ShortcutStore()
    private lazy var model = PetModel(engine: engine, preferences: preferences, shortcuts: shortcuts)
    private let alerts = AlertService()

    private var panel: FloatingPanel!
    private var settingsWindow: NSWindow?
    private var ticker: Timer?

    // Drag state, in screen coordinates.
    private var dragStartMouse: NSPoint?
    private var dragStartOrigin: NSPoint = .zero
    private var dragMoved = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        alerts.setUp()

        preferences.onChange = { [weak self] in
            guard let self else { return }
            engine.config = preferences.timerConfig
            // Let SwiftUI lay out the new pet size, then fit the panel to it.
            DispatchQueue.main.async { self.fitPanelToContent() }
        }

        engine.onPhaseEnded = { [weak self] ended, next in
            guard let self else { return }
            model.celebrate()
            alerts.phaseEnded(ended, next: next, preferences: preferences)
        }

        model.openSettings = { [weak self] in self?.showSettings() }
        model.hidePet = { [weak self] in self?.panel.orderOut(nil) }
        model.dragChanged = { [weak self] in self?.dragChanged() ?? false }
        model.dragEnded = { [weak self] in self?.dragEnded() ?? false }

        panel = FloatingPanel(rootView: PetView(model: model))
        placePanel()
        panel.orderFrontRegardless()

        // Time left comes from the end date, so a 4 Hz tick is enough and survives sleep.
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.engine.tick()
        }
        RunLoop.main.add(ticker!, forMode: .common)

        HotKeys.shared.setAction(for: .toggle) { [weak self] in self?.engine.toggle() }
        HotKeys.shared.setAction(for: .skip) { [weak self] in self?.engine.skip() }
        HotKeys.shared.setAction(for: .showHide) { [weak self] in self?.togglePanel() }
        shortcuts.onChange = { [weak self] in self?.applyShortcuts() }
        applyShortcuts()
    }

    private func applyShortcuts() {
        shortcuts.report(failed: HotKeys.shared.apply(shortcuts))
    }

    /// Opening Tomo again (for example from Finder) brings the pet back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.orderFrontRegardless()
        return true
    }

    // MARK: - Panel

    private func placePanel() {
        let autosaveName = "TomoPanel"
        let hasSavedFrame = UserDefaults.standard.string(forKey: "NSWindow Frame \(autosaveName)") != nil
        panel.setFrameAutosaveName(autosaveName)
        fitPanelToContent()
        if !hasSavedFrame, let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - panel.frame.width - 24, y: screen.minY + 24))
        }
    }

    /// Resizes the panel to the SwiftUI content and keeps its bottom edge in place.
    private func fitPanelToContent() {
        guard let content = panel.contentView else { return }
        let size = content.fittingSize
        var frame = panel.frame
        frame.origin.x += (frame.width - size.width) / 2
        frame.size = size
        panel.setFrame(frame, display: true)
    }

    private func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// Moves the panel with the mouse. Returns true once the mouse has moved more than a few points.
    private func dragChanged() -> Bool {
        let mouse = NSEvent.mouseLocation
        if dragStartMouse == nil {
            dragStartMouse = mouse
            dragStartOrigin = panel.frame.origin
            dragMoved = false
        }
        guard let start = dragStartMouse else { return false }
        let dx = mouse.x - start.x
        let dy = mouse.y - start.y
        if !dragMoved && hypot(dx, dy) > 3 { dragMoved = true }
        if dragMoved {
            let origin = NSPoint(x: dragStartOrigin.x + dx, y: dragStartOrigin.y + dy)
            panel.setFrameOrigin(clamped(origin, mouse: mouse))
        }
        return dragMoved
    }

    /// Lets Tomo go anywhere, even over the menu bar or partly off the edge,
    /// but keeps at least a small part on the screen so you can grab it again.
    private func clamped(_ origin: NSPoint, mouse: NSPoint) -> NSPoint {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? panel.screen else { return origin }
        let bounds = screen.frame
        let keep: CGFloat = 40
        let size = panel.frame.size
        return NSPoint(
            x: min(max(origin.x, bounds.minX - size.width + keep), bounds.maxX - keep),
            y: min(max(origin.y, bounds.minY - size.height + keep), bounds.maxY - keep)
        )
    }

    private func dragEnded() -> Bool {
        let moved = dragMoved
        dragStartMouse = nil
        dragMoved = false
        if moved { panel.saveFrame(usingName: "TomoPanel") }
        return moved
    }

    // MARK: - Settings

    private func showSettings() {
        if settingsWindow == nil {
            let settings = SettingsView(preferences: preferences, loginItem: LoginItem(), shortcuts: shortcuts)
            let window = NSWindow(contentViewController: NSHostingController(rootView: settings))
            window.title = "Tomo Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            // Stop waiting for new shortcut keys when the window closes.
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                self?.shortcuts.stopRecording()
            }
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
