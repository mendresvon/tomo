import AppKit
import TomoCore

/// Command line helpers used by the build script and for checking the art.
///
///     Tomo --export-sprites <folder>   Writes every animation frame as a PNG.
///     Tomo --export-window <file.png>  Writes the floating window in each timer state.
///     Tomo --export-icon <file.png>    Writes the 1024 x 1024 app icon.
///     Tomo --export-settings <file.png> Writes the Settings window.
@MainActor
enum Export {
    /// Returns true when the arguments asked for an export (the app then exits).
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--export-sprites"), i + 1 < args.count {
            exportSprites(to: URL(fileURLWithPath: args[i + 1]))
            return true
        }
        if let i = args.firstIndex(of: "--export-window"), i + 1 < args.count {
            exportWindow(to: URL(fileURLWithPath: args[i + 1]))
            return true
        }
        if let i = args.firstIndex(of: "--export-icon"), i + 1 < args.count {
            exportIcon(to: URL(fileURLWithPath: args[i + 1]))
            return true
        }
        if let i = args.firstIndex(of: "--export-settings"), i + 1 < args.count {
            exportSettings(to: URL(fileURLWithPath: args[i + 1]))
            return true
        }
        return false
    }

    /// One strip per mood, on a checkerboard so transparent areas are visible.
    private static func exportSprites(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pixel: CGFloat = 8
        let side = CGFloat(Sprites.canvasSize) * pixel
        for mood in Mood.allCases {
            let frames = Sprites.animation(for: mood).frames
            let size = CGSize(width: CGFloat(frames.count) * (side + 8) + 8, height: side + 16)
            write(size: size, to: folder.appendingPathComponent("\(mood.rawValue).png")) { context in
                context.setFillColor(.white)
                context.fill(CGRect(origin: .zero, size: size))
                for (i, frame) in frames.enumerated() {
                    let x = 8 + CGFloat(i) * (side + 8)
                    context.setFillColor(CGColor(gray: 0.9, alpha: 1))
                    for row in 0..<Int(side / 8) {
                        for col in 0..<Int(side / 8) where (row + col) % 2 == 0 {
                            context.fill(CGRect(x: x + CGFloat(col) * 8, y: 8 + CGFloat(row) * 8, width: 8, height: 8))
                        }
                    }
                    Sprites.draw(frame, in: context, pixel: pixel, originX: x, originY: 8 + side)
                }
            }
        }
    }

    /// Renders the floating window in each timer state, on a light and a dark background.
    private static func exportWindow(to url: URL) {
        let preferences = Preferences()
        let shortcuts = ShortcutStore()
        func pet(_ setUp: (TimerEngine) -> Void) -> PetView {
            let engine = TimerEngine(config: TimerConfig(focus: 25 * 60))
            setUp(engine)
            let view = PetView(engine: engine, preferences: preferences, shortcuts: shortcuts)
            view.setContentsScale(2)
            return view
        }
        let views = [
            pet { _ in },
            pet { $0.start() },
            pet { $0.start(); $0.pause() },
            pet { $0.skip(); $0.start() },
        ]
        let cell = views[0].contentSize
        let size = CGSize(width: cell.width * CGFloat(views.count) * 2, height: cell.height * 4)
        write(size: size, to: url) { context in
            context.scaleBy(x: 2, y: 2)
            for (row, gray) in [(1, 1.0), (0, 0.12)] {
                context.setFillColor(CGColor(gray: gray, alpha: 1))
                context.fill(CGRect(x: 0, y: CGFloat(row) * cell.height, width: size.width, height: cell.height))
                for (i, view) in views.enumerated() {
                    context.saveGState()
                    context.translateBy(x: CGFloat(i) * cell.width, y: CGFloat(row) * cell.height)
                    view.layer?.render(in: context)
                    context.restoreGState()
                }
            }
        }
    }

    /// The app icon: Tomo on a soft rounded square.
    private static func exportIcon(to url: URL) {
        let size = CGSize(width: 1024, height: 1024)
        write(size: size, to: url) { context in
            let square = CGRect(x: 100, y: 100, width: 824, height: 824)
            context.addPath(CGPath(roundedRect: square, cornerWidth: 185, cornerHeight: 185, transform: nil))
            context.clip()
            let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [cgColor(0xFFF4E2), cgColor(0xFFD9C7)] as CFArray,
                locations: [0, 1]
            )!
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: square.maxY), end: CGPoint(x: 0, y: square.minY), options: [])
            context.resetClip()
            let pixel: CGFloat = 30
            let side = CGFloat(Sprites.canvasSize) * pixel
            let origin = (1024 - side) / 2
            Sprites.draw(Sprites.animation(for: .idle).frames[0], in: context, pixel: pixel, originX: origin, originY: origin + side)
        }
    }

    private static func exportSettings(to url: URL) {
        let controller = SettingsWindowController(preferences: Preferences(), shortcuts: ShortcutStore())
        guard let view = controller.window?.contentView else { return }
        view.layoutSubtreeIfNeeded()
        view.setFrameSize(view.fittingSize)
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("Wrote \(url.path)")
    }

    private static func write(size: CGSize, to url: URL, draw: (CGContext) -> Void) {
        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        draw(context)
        guard let image = context.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write(Data("Could not render \(url.lastPathComponent)\n".utf8))
            return
        }
        try? png.write(to: url)
        print("Wrote \(url.path)")
    }
}
