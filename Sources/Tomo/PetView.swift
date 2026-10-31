import AppKit
import TomoCore

/// Tomo and the timer badge beside it, drawn with Core Animation layers.
///
/// The pet animation is a looping Core Animation keyframe animation, so it runs
/// without any work from Tomo's own code. The badge changes at most once a second.
final class PetView: NSView {
    private let engine: TimerEngine
    private let preferences: Preferences
    private let shortcuts: ShortcutStore

    var onTap: () -> Void = {}
    var openSettings: () -> Void = {}
    var hidePet: () -> Void = {}
    var dragChanged: () -> Bool = { false }
    var dragEnded: () -> Bool = { false }

    /// True for a few seconds after a phase ends.
    var celebrating = false {
        didSet { if celebrating != oldValue { render() } }
    }

    /// When true, Tomo holds still on the first frame of its mood, so the screen does not change.
    var still = false {
        didSet {
            guard still != oldValue else { return }
            shownMood = nil
            render()
        }
    }

    /// The size the panel must have to show everything.
    private(set) var contentSize = NSSize.zero

    private let root = CALayer()
    private let petLayer = CALayer()
    private let badge = CALayer()
    private let timeText = CATextLayer()
    private let captionText = CATextLayer()
    private var blocks: [CALayer] = []
    private let blockCount = 10

    private var hovering = false
    private var pixel: CGFloat = 0
    // The last values drawn, so nothing is redrawn when nothing changed.
    private var shownMood: Mood?
    private var shownTime = ""
    private var shownCaption = ""
    private var shownColor: UInt32 = 0
    private var shownFilled = -1

    init(engine: TimerEngine, preferences: Preferences, shortcuts: ShortcutStore) {
        self.engine = engine
        self.preferences = preferences
        self.shortcuts = shortcuts
        super.init(frame: .zero)

        // A layer-hosting view: the layers below are the whole drawing.
        layer = root
        wantsLayer = true
        root.actions = Self.noAnimations

        petLayer.magnificationFilter = .nearest
        petLayer.contentsGravity = .resize
        // Squash from the feet, not the middle.
        petLayer.anchorPoint = CGPoint(x: 0.5, y: 0)
        petLayer.actions = Self.noAnimations
        root.addSublayer(petLayer)

        badge.backgroundColor = cgColor(0x2A1620, alpha: 0.82)
        badge.cornerCurve = .continuous
        badge.actions = Self.noAnimations
        root.addSublayer(badge)

        for text in [timeText, captionText] {
            text.alignmentMode = .center
            text.actions = Self.noAnimations
            badge.addSublayer(text)
        }
        timeText.foregroundColor = .white
        captionText.foregroundColor = CGColor(gray: 1, alpha: 0.75)

        for _ in 0..<blockCount {
            let block = CALayer()
            block.actions = Self.noAnimations
            badge.addSublayer(block)
            blocks.append(block)
        }

        toolTip = "Click: start or pause. Drag: move. Right-click: menu."
        applySize()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Turns off Core Animation's default fades, which would draw extra frames.
    private static let noAnimations: [String: CAAction] = [
        "contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "frame": NSNull(),
        "string": NSNull(), "backgroundColor": NSNull(), "borderColor": NSNull(),
        "foregroundColor": NSNull(), "hidden": NSNull(), "sublayers": NSNull(),
    ]

    // MARK: - Layout

    /// Lays out every layer for the current pet size. Call it after the size setting changes.
    func applySize() {
        let pixel = preferences.petSize.pixelSize
        guard pixel != self.pixel else { return }
        self.pixel = pixel
        let s = pixel / 5  // badge scale, 1 at medium size

        let timeFont = Self.roundedFont(size: 18 * s, weight: .heavy)
        let captionFont = Self.roundedFont(size: 8 * s, weight: .bold)
        let timeHeight = ceil(timeFont.ascender - timeFont.descender)
        let captionHeight = ceil(captionFont.ascender - captionFont.descender)

        let barWidth = CGFloat(blockCount) * 6 * s + CGFloat(blockCount - 1) * 2 * s
        let badgeWidth = barWidth + 20 * s
        let badgeHeight = 6 * s + timeHeight + 3 * s + captionHeight + 3 * s + 5 * s + 6 * s

        let pad = pixel
        let petSide = CGFloat(Sprites.canvasSize) * pixel
        contentSize = NSSize(width: pad + petSide + pixel + badgeWidth + pad, height: pad + petSide + pad)
        setFrameSize(contentSize)
        root.frame = CGRect(origin: .zero, size: contentSize)

        petLayer.bounds = CGRect(x: 0, y: 0, width: petSide, height: petSide)
        petLayer.position = CGPoint(x: pad + petSide / 2, y: pad)

        // Line the badge up with Tomo's body, below the room kept for jumps and Zs.
        let badgeTop = pad + (petSide - (badgeHeight + 4 * pixel)) / 2 + 4 * pixel
        badge.frame = CGRect(x: pad + petSide + pixel, y: contentSize.height - badgeTop - badgeHeight, width: badgeWidth, height: badgeHeight)
        badge.cornerRadius = 10 * s
        badge.borderWidth = 2 * s

        timeText.font = timeFont
        timeText.fontSize = timeFont.pointSize
        timeText.frame = CGRect(x: 0, y: badgeHeight - 6 * s - timeHeight, width: badgeWidth, height: timeHeight)
        captionText.font = captionFont
        captionText.fontSize = captionFont.pointSize
        captionText.frame = CGRect(x: 0, y: timeText.frame.minY - 3 * s - captionHeight, width: badgeWidth, height: captionHeight)

        for (i, block) in blocks.enumerated() {
            block.frame = CGRect(x: 10 * s + CGFloat(i) * 8 * s, y: 6 * s, width: 6 * s, height: 5 * s)
        }
    }

    /// Text is drawn into bitmaps, so it needs the screen's pixel density to stay sharp.
    func setContentsScale(_ scale: CGFloat) {
        timeText.contentsScale = scale
        captionText.contentsScale = scale
        // Redraw the text at the new density.
        shownTime = ""
        shownCaption = ""
        render()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        setContentsScale(window?.backingScaleFactor ?? 2)
    }

    private static func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: rounded, size: size) ?? base
    }

    // MARK: - Drawing

    /// Brings the layers up to date with the timer. Only changed values are touched.
    func render() {
        let mood = currentMood
        if mood != shownMood { play(mood) }

        let total = Int(engine.remaining.rounded(.up))
        let time = String(format: "%02d:%02d", total / 60, total % 60)
        let caption = currentCaption
        let color = phaseColor
        let filled = Int((engine.progress * Double(blockCount)).rounded(.down))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if time != shownTime { timeText.string = time; shownTime = time }
        if caption != shownCaption { captionText.string = caption; shownCaption = caption }
        if color != shownColor || filled != shownFilled {
            badge.borderColor = cgColor(color, alpha: 0.9)
            let empty = CGColor(gray: 1, alpha: 0.18)
            let full = cgColor(color)
            for (i, block) in blocks.enumerated() { block.backgroundColor = i < filled ? full : empty }
            shownColor = color
            shownFilled = filled
        }
        CATransaction.commit()
    }

    private var currentMood: Mood {
        if celebrating { return .celebrate }
        switch engine.state {
        case .running: return engine.phase == .focus ? .focus : .rest
        case .paused: return .sleep
        case .idle: return .idle
        }
    }

    private var currentCaption: String {
        if hovering && engine.state == .idle { return "click to start" }
        if engine.phase == .focus {
            return "FOCUS \(engine.currentRound)/\(engine.config.roundsBeforeLongBreak)"
        }
        return engine.phase == .longBreak ? "LONG BREAK" : "BREAK"
    }

    private var phaseColor: UInt32 {
        switch engine.phase {
        case .focus: return 0xFF5B5B
        case .shortBreak: return 0x5CC96B
        case .longBreak: return 0x4D9DE0
        }
    }

    /// Hands the mood's frames to Core Animation, which loops them on its own.
    private func play(_ mood: Mood) {
        shownMood = mood
        let images = Sprites.images(for: mood)
        let fps = Sprites.animation(for: mood).fps
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        petLayer.removeAnimation(forKey: "frames")
        petLayer.contents = images.first
        if images.count > 1 && !still {
            let frames = CAKeyframeAnimation(keyPath: "contents")
            frames.values = images
            frames.calculationMode = .discrete
            // Discrete animations take one more key time than values.
            frames.keyTimes = (0...images.count).map { NSNumber(value: Double($0) / Double(images.count)) }
            frames.duration = Double(images.count) / fps
            frames.repeatCount = .infinity
            frames.isRemovedOnCompletion = false
            petLayer.add(frames, forKey: "frames")
        }
        CATransaction.commit()
    }

    /// A quick squash and bounce when you click Tomo.
    private func squash() {
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = NSValue(caTransform3D: CATransform3DMakeScale(1.12, 0.86, 1))
        spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        spring.mass = 1
        spring.stiffness = 400
        spring.damping = 9
        spring.duration = spring.settlingDuration
        petLayer.add(spring, forKey: "squash")
    }

    // MARK: - Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { _ = dragChanged() }
    override func mouseDragged(with event: NSEvent) { _ = dragChanged() }

    override func mouseUp(with event: NSEvent) {
        if !dragEnded() {
            onTap()
            squash()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; render() }
    override func mouseExited(with event: NSEvent) { hovering = false; render() }

    // MARK: - Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let toggleTitle = engine.state == .running ? "Pause" : engine.state == .paused ? "Resume" : "Start"
        menu.addItem(ClosureMenuItem(toggleTitle) { [weak self] in self?.engine.toggle() })
        menu.addItem(ClosureMenuItem("Skip to Next Phase") { [weak self] in self?.engine.skip() })
        menu.addItem(ClosureMenuItem("Reset") { [weak self] in self?.engine.reset() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Settings…") { [weak self] in self?.openSettings() })
        let showKeys = shortcuts.combo(for: .showHide).label
        menu.addItem(ClosureMenuItem("Hide Tomo (\(showKeys) to show)") { [weak self] in self?.hidePet() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Quit Tomo") { NSApp.terminate(nil) })
        return menu
    }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { handler() }
}
