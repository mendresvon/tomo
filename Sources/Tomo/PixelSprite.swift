import SwiftUI

/// Draws one pet frame as crisp square pixels.
struct PixelSprite: View {
    let frame: PetFrame
    /// Screen points per sprite pixel. Whole numbers keep the edges sharp.
    let pixelSize: CGFloat

    var body: some View {
        let side = CGFloat(Sprites.canvasSize) * pixelSize
        Canvas { context, _ in
            for layer in frame.layers {
                for (row, line) in layer.grid.enumerated() {
                    for (col, char) in line.enumerated() where char != "." {
                        guard let color = Sprites.palette[char] else { continue }
                        let x = layer.x + col
                        let y = layer.y + row
                        guard (0..<Sprites.canvasSize).contains(x), (0..<Sprites.canvasSize).contains(y) else { continue }
                        let rect = CGRect(x: CGFloat(x) * pixelSize, y: CGFloat(y) * pixelSize, width: pixelSize, height: pixelSize)
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }
        }
        .frame(width: side, height: side)
    }
}

/// Plays a mood's animation in a loop.
struct AnimatedPet: View {
    let mood: Mood
    let pixelSize: CGFloat

    var body: some View {
        let animation = Sprites.animation(for: mood)
        TimelineView(.periodic(from: .now, by: 1 / animation.fps)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate * animation.fps)
            PixelSprite(frame: animation.frames[tick % animation.frames.count], pixelSize: pixelSize)
        }
    }
}
