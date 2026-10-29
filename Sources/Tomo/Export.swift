import AppKit
import SwiftUI
import TomoCore

/// Command line helpers used by the build script and for checking the art.
///
///     Tomo --export-sprites <folder>   Writes every animation frame as a PNG.
///     Tomo --export-window <file.png>  Writes the floating window in each timer state.
///     Tomo --export-icon <file.png>    Writes the 1024 x 1024 app icon.
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
            write(IconView(), to: URL(fileURLWithPath: args[i + 1]))
            return true
        }
        return false
    }

    private static func exportSprites(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for mood in Mood.allCases {
            let frames = Sprites.animation(for: mood).frames
            // One strip per mood, on a checkerboard so transparent areas are visible.
            let strip = HStack(spacing: 8) {
                ForEach(frames.indices, id: \.self) { i in
                    PixelSprite(frame: frames[i], pixelSize: 8).background(Checkerboard())
                }
            }
            .padding(8)
            .background(Color.white)
            write(strip, to: folder.appendingPathComponent("\(mood.rawValue).png"))
        }
    }

    /// Renders the floating window in each timer state, on a light and a dark background.
    private static func exportWindow(to url: URL) {
        func pet(_ setUp: (TimerEngine) -> Void) -> some View {
            let engine = TimerEngine(config: TimerConfig(focus: 25 * 60))
            setUp(engine)
            return PetView(model: PetModel(engine: engine, preferences: Preferences(), shortcuts: ShortcutStore()))
        }
        let states = HStack(spacing: 0) {
            pet { _ in }
            pet { $0.start() }
            pet { $0.start(); $0.pause() }
            pet { $0.skip(); $0.start() }
        }
        let sheet = VStack(spacing: 0) {
            states.background(Color.white)
            states.background(Color(white: 0.12))
        }
        write(sheet, to: url)
    }

    private static func write<V: View>(_ view: V, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write(Data("Could not render \(url.lastPathComponent)\n".utf8))
            return
        }
        try? png.write(to: url)
        print("Wrote \(url.path)")
    }
}

/// The app icon: Tomo on a soft rounded square.
private struct IconView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xFFF4E2), Color(hex: 0xFFD9C7)], startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
            PixelSprite(frame: Sprites.animation(for: .idle).frames[0], pixelSize: 30)
        }
        .frame(width: 1024, height: 1024)
    }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 8
            for row in 0..<Int(size.height / cell) {
                for col in 0..<Int(size.width / cell) where (row + col) % 2 == 0 {
                    context.fill(Path(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)), with: .color(Color(white: 0.9)))
                }
            }
        }
    }
}
