import AppKit
import SwiftUI

/// A borderless, transparent panel that floats above every app,
/// on every desktop (Space), and over full-screen apps.
final class FloatingPanel: NSPanel {
    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // Above the menu bar, so Tomo can sit at the very top of the screen.
        // Set this after isFloatingPanel, which resets the level to .floating.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false

        let hosting = ClickThroughHostingView(rootView: rootView)
        contentView = hosting
        setContentSize(hosting.fittingSize)
    }

    // Tomo never takes keyboard focus from the app you are using.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // macOS normally keeps windows below the menu bar. Tomo may go anywhere,
    // and the drag code keeps part of it on screen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Accepts the first click even though the panel is never the active window,
/// so one click on Tomo starts or pauses the timer.
private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
