import AppKit
import TomoCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
    private let shortcuts = ShortcutStore()
    private lazy var engine = TimerEngine(config: preferences.timerConfig)
    private let alerts = AlertService()

    private var panel: FloatingPanel!
    private var petView: PetView!
    private var settings: SettingsWindowController?

    // Timers run only while the timer runs. When Tomo is visible, one fires each time
    // the shown second changes. When Tomo is hidden or covered, one fires at the end only.
    private var clock: Timer?
    private var clockKey: ClockKey?
    private var celebrateTimer: Timer?
    private var renderPending = false

    private struct ClockKey: Equatable {
        var endsAt: Date?
        var visible: Bool
    }

    // Drag state, in screen coordinates.
    private var dragStartMouse: NSPoint?
    private var dragStartOrigin: NSPoint = .zero
    private var dragMoved = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        alerts.setUp()

        preferences.onChange = { [weak self] in
            guard let self else { return }
            engine.config = preferences.timerConfig
            petView.applySize()
            fitPanelToContent()
            setNeedsRender()
        }

        engine.onChange = { [weak self] in self?.setNeedsRender() }
        engine.onPhaseEnded = { [weak self] ended, next in
            guard let self else { return }
            celebrate()
            alerts.phaseEnded(ended, next: next, preferences: preferences)
        }

        petView = PetView(engine: engine, preferences: preferences, shortcuts: shortcuts)
        petView.onTap = { [weak self] in
            self?.petView.celebrating = false
            self?.engine.toggle()
        }
        petView.openSettings = { [weak self] in self?.showSettings() }
        petView.hidePet = { [weak self] in self?.setPanelVisible(false) }
        petView.dragChanged = { [weak self] in self?.dragChanged() ?? false }
        petView.dragEnded = { [weak self] in self?.dragEnded() ?? false }

        panel = FloatingPanel(view: petView)
        placePanel()
        panel.orderFrontRegardless()

        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: panel, queue: .main) { [weak self] _ in
            self?.setNeedsRender()
        }
        // Timers pause while the Mac sleeps, so catch up after it wakes.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            clockKey = nil
            engine.tick()
            setNeedsRender()
        }

        HotKeys.shared.setAction(for: .toggle) { [weak self] in self?.engine.toggle() }
        HotKeys.shared.setAction(for: .skip) { [weak self] in self?.engine.skip() }
        HotKeys.shared.setAction(for: .showHide) { [weak self] in self?.togglePanel() }
        shortcuts.onChange = { [weak self] in self?.applyShortcuts() }
        applyShortcuts()

        // `open Tomo.app --args --start` starts a focus round right away.
        if CommandLine.arguments.contains("--start") { engine.start() }
        render()
    }

    /// Opening Tomo again (for example from Finder) brings the pet back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        setPanelVisible(true)
        return true
    }

    private func applyShortcuts() {
        shortcuts.report(failed: HotKeys.shared.apply(shortcuts))
    }

    // MARK: - Rendering and timers

    /// The engine reports each value change on its own. This draws once for all of them.
    private func setNeedsRender() {
        guard !renderPending else { return }
        renderPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            renderPending = false
            render()
        }
    }

    private func render() {
        petView.render()
        updateClock()
    }

    private func updateClock() {
        let visible = panel.isVisible && panel.occlusionState.contains(.visible)
        let key = ClockKey(endsAt: engine.endsAt, visible: visible)
        guard key != clockKey else { return }
        clockKey = key
        clock?.invalidate()
        clock = nil
        guard let end = key.endsAt else { return }

        let timer: Timer
        if visible {
            // Fire just after each whole second of time left, when the shown time changes.
            let left = end.timeIntervalSinceNow
            let first = Date().addingTimeInterval(left - left.rounded(.down) + 0.02)
            timer = Timer(fire: first, interval: 1, repeats: true) { [weak self] _ in self?.engine.tick() }
            timer.tolerance = 0.05
        } else {
            timer = Timer(fire: end.addingTimeInterval(0.02), interval: 0, repeats: false) { [weak self] _ in self?.engine.tick() }
            timer.tolerance = 0.2
        }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
    }

    private func celebrate() {
        petView.celebrating = true
        celebrateTimer?.invalidate()
        celebrateTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            self?.petView.celebrating = false
        }
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

    /// Resizes the panel to the pet view and keeps its bottom edge in place.
    private func fitPanelToContent() {
        let size = petView.contentSize
        var frame = panel.frame
        frame.origin.x += (frame.width - size.width) / 2
        frame.size = size
        panel.setFrame(frame, display: true)
    }

    private func setPanelVisible(_ visible: Bool) {
        if visible {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
        setNeedsRender()
    }

    private func togglePanel() {
        setPanelVisible(!panel.isVisible)
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
        if settings == nil {
            let controller = SettingsWindowController(preferences: preferences, shortcuts: shortcuts)
            // Free the window and its controls once it closes.
            controller.onClose = { [weak self] in
                DispatchQueue.main.async { self?.settings = nil }
            }
            settings = controller
        }
        NSApp.activate(ignoringOtherApps: true)
        settings?.showWindow(nil)
        settings?.window?.makeKeyAndOrderFront(nil)
    }
}
