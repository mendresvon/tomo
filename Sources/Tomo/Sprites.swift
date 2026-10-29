import CoreGraphics

/// What Tomo is doing. Each mood has its own animation.
enum Mood: String, CaseIterable {
    case idle, focus, rest, sleep, celebrate
}

/// A pixel grid drawn at a position on the canvas. "." is transparent.
struct Layer {
    var grid: [String]
    var x: Int
    var y: Int
}

struct PetFrame {
    var layers: [Layer]
}

struct PetAnimation {
    var fps: Double
    var frames: [PetFrame]
}

/// Tomo's pixel art. Every frame is built from text grids, one character per pixel.
enum Sprites {
    /// The canvas is a square of this many pixels.
    static let canvasSize = 24

    /// Colors as 0xRRGGBB. "S" is the only see-through color.
    static let palette: [Character: UInt32] = [
        "K": 0x3D2333,  // outline
        "R": 0xFF5B5B,  // body
        "D": 0xD93F4C,  // body shade
        "H": 0xFFA8A0,  // body highlight
        "G": 0x5CC96B,  // leaf
        "g": 0x2F8F4E,  // leaf shade and stem
        "k": 0x2A1620,  // eyes and mouth
        "W": 0xFFFFFF,  // eye shine
        "P": 0xFF8FAB,  // cheeks
        "B": 0x4D9DE0,  // headband
        "L": 0xC3CCDA,  // laptop lid
        "l": 0xFFFFFF,  // laptop logo
        "A": 0x8592A8,  // laptop base
        "T": 0xC9824A,  // tea
        "M": 0xFFF4E2,  // mug
        "s": 0xB8C4D6,  // steam
        "z": 0x7FA7FF,  // sleep Z
        "Y": 0xFFD23F,  // sparkle
        "S": 0x000000,  // ground shadow (drawn at 18% opacity)
    ]
    private static let shadowAlpha: CGFloat = 0.18

    /// One small image per frame, one image pixel per sprite pixel (24 x 24).
    /// Core Animation scales them up with nearest-neighbor filtering, so they stay sharp
    /// and use almost no memory. Built once per mood, then reused.
    static func images(for mood: Mood) -> [CGImage] {
        if let cached = imageCache[mood] { return cached }
        let images = animation(for: mood).frames.compactMap { image(of: $0) }
        imageCache[mood] = images
        return images
    }

    nonisolated(unsafe) private static var imageCache: [Mood: [CGImage]] = [:]

    /// Draws a frame into a bitmap. `scale` is image pixels per sprite pixel.
    static func image(of frame: PetFrame, scale: Int = 1) -> CGImage? {
        let side = canvasSize * scale
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        draw(frame, in: context, pixel: CGFloat(scale), originY: CGFloat(side))
        return context.makeImage()
    }

    /// Fills one square per sprite pixel. The context has y going up, so rows are
    /// drawn down from `originY`.
    static func draw(_ frame: PetFrame, in context: CGContext, pixel: CGFloat, originX: CGFloat = 0, originY: CGFloat) {
        for layer in frame.layers {
            for (row, line) in layer.grid.enumerated() {
                for (col, char) in line.enumerated() where char != "." {
                    guard let hex = palette[char] else { continue }
                    let x = layer.x + col
                    let y = layer.y + row
                    guard (0..<canvasSize).contains(x), (0..<canvasSize).contains(y) else { continue }
                    context.setFillColor(cgColor(hex, alpha: char == "S" ? shadowAlpha : 1))
                    context.fill(CGRect(x: originX + CGFloat(x) * pixel, y: originY - CGFloat(y + 1) * pixel, width: pixel, height: pixel))
                }
            }
        }
    }

    static func animation(for mood: Mood) -> PetAnimation {
        switch mood {
        case .idle: return idle
        case .focus: return focus
        case .rest: return rest
        case .sleep: return sleep
        case .celebrate: return celebrate
        }
    }

    // MARK: - Body parts (16 x 16, body coordinates)

    private static let body = [
        ".......gg.......",
        "...gGGGggGGGg...",
        "....KKgGGgKK....",
        "..KKRRRRRRRRKK..",
        ".KRRHHRRRRRRRRK.",
        ".KRHHRRRRRRRRRK.",
        "KRRHRRRRRRRRRRRK",
        "KRRRRRRRRRRRRRRK",
        "KRRRRRRRRRRRRRRK",
        "KRRRRRRRRRRRRRRK",
        "KRRRRRRRRRRRRRDK",
        ".KRRRRRRRRRRDDK.",
        "..KDDRRRRRRDDK..",
        "...KKDDDDDDKK...",
        ".....KKKKKK.....",
        "....KK....KK....",
    ]

    /// Faces cover body rows 6 to 11.
    private static let faceTop = 6

    private static let faceOpen = [
        "....kW....kW....",
        "....kk....kk....",
        "....kk....kk....",
        "..PP..k..k..PP..",
        ".......kk.......",
    ]

    private static let faceBlink = [
        "................",
        "................",
        "....kk....kk....",
        "..PP..k..k..PP..",
        ".......kk.......",
    ]

    private static let faceFocus = [
        "................",
        "....kk....kk....",
        "....kk....kk....",
        "..PP........PP..",
        ".......kkk......",
        ".........P......",
    ]

    private static let faceHappy = [
        "................",
        "....k......k....",
        "...k.k....k.k...",
        "..PP..kkkk..PP..",
        ".......kk.......",
    ]

    private static let faceSleep = [
        "................",
        "................",
        "...kkk....kkk...",
        "..PP........PP..",
        ".......kk.......",
    ]

    private static let faceExcited = [
        "....kW....kW....",
        "....kk....kk....",
        "....kk....kk....",
        "..PP..kkkk..PP..",
        "......kPPk......",
        ".......kk.......",
    ]

    private static let headbandA = [
        ".BBBBBBWWBBBBBBBB",
        "...............BB",
        "................B",
    ]

    private static let headbandB = [
        ".BBBBBBWWBBBBBBBBB",
        "................BB",
    ]

    private static let laptop = [
        ".KKKKKKKKKK.",
        ".KLLLllLLLK.",
        ".KLLLLLLLLK.",
        "KAAAAAAAAAAK",
        "KKKKKKKKKKKK",
    ]

    private static let hand = ["RR"]

    private static let mugA = [
        "...s.s.",
        "....s..",
        "KKKKK..",
        "KTTTKK.",
        "KMMMK.K",
        "KMMMKK.",
        ".KKK...",
    ]

    private static let mugB = [
        "....s.s",
        "...s...",
        "KKKKK..",
        "KTTTKK.",
        "KMMMK.K",
        "KMMMKK.",
        ".KKK...",
    ]

    private static let bigZ = ["zzzz", "..z.", ".z..", "zzzz"]
    private static let sparkle = [".Y.", "YYY", ".Y."]
    private static let dot = ["Y"]

    // MARK: - Frame builder

    /// Builds one frame: shadow, body, face, then extras in body coordinates,
    /// then free layers in canvas coordinates.
    private static func frame(
        dx: Int = 0, dy: Int = 0, face: [String],
        extras: [Layer] = [], free: [Layer] = [], wideShadow: Bool = true
    ) -> PetFrame {
        let ox = 4 + dx
        let oy = 5 + dy
        var layers: [Layer] = []
        layers.append(wideShadow ? Layer(grid: ["SSSSSSSSSS"], x: 7, y: 21) : Layer(grid: ["SSSSSS"], x: 9, y: 21))
        layers.append(Layer(grid: body, x: ox, y: oy))
        layers.append(Layer(grid: face, x: ox, y: oy + faceTop))
        layers += extras.map { Layer(grid: $0.grid, x: ox + $0.x, y: oy + $0.y) }
        layers += free
        return PetFrame(layers: layers)
    }

    // MARK: - Animations

    /// Awake and waiting: a small hop now and then, and a blink.
    private static let idle = PetAnimation(fps: 3, frames: [
        frame(face: faceOpen),
        frame(face: faceOpen),
        frame(dy: -1, face: faceOpen),
        frame(dy: -1, face: faceOpen),
        frame(face: faceOpen),
        frame(face: faceBlink),
        frame(face: faceOpen),
        frame(face: faceOpen),
    ])

    /// Working hard: headband on, typing on a tiny laptop.
    private static let focus: PetAnimation = {
        func typing(_ leftUp: Bool, band: [String], dy: Int) -> PetFrame {
            frame(dy: dy, face: faceFocus, extras: [
                Layer(grid: band, x: 0, y: 4),
                Layer(grid: laptop, x: 2, y: 12),
                Layer(grid: hand, x: 4, y: leftUp ? 14 : 15),
                Layer(grid: hand, x: 10, y: leftUp ? 15 : 14),
            ])
        }
        return PetAnimation(fps: 5, frames: [
            typing(true, band: headbandA, dy: 0),
            typing(false, band: headbandB, dy: 0),
            typing(true, band: headbandA, dy: 0),
            typing(false, band: headbandB, dy: 1),
        ])
    }()

    /// On a break: happy face, swaying, holding a warm mug.
    private static let rest = PetAnimation(fps: 2.5, frames: [
        frame(face: faceHappy, extras: [Layer(grid: mugA, x: 13, y: 10)]),
        frame(dx: -1, face: faceHappy, extras: [Layer(grid: mugB, x: 13, y: 10)]),
        frame(face: faceHappy, extras: [Layer(grid: mugA, x: 13, y: 10)]),
        frame(dx: -1, face: faceHappy, extras: [Layer(grid: mugB, x: 13, y: 10)]),
    ])

    /// Paused: asleep, with Zs floating up.
    private static let sleep: PetAnimation = {
        let path = [(17, 5), (18, 3), (19, 1), (20, -2)]
        var frames: [PetFrame] = []
        for i in 0..<4 {
            let a = path[i]
            let b = path[(i + 2) % 4]
            frames.append(frame(dy: i % 2 == 0 ? 0 : 1, face: faceSleep, free: [
                Layer(grid: bigZ, x: a.0, y: a.1),
                Layer(grid: bigZ, x: b.0, y: b.1),
            ]))
        }
        return PetAnimation(fps: 2, frames: frames)
    }()

    /// A phase just ended: jumping with sparkles.
    private static let celebrate: PetAnimation = {
        let hops = [0, -2, -4, -4, -2, 0, 0, 0]
        var frames: [PetFrame] = []
        for (i, dy) in hops.enumerated() {
            let sparkles: [Layer] = i % 2 == 0
                ? [Layer(grid: sparkle, x: 1, y: 3), Layer(grid: sparkle, x: 20, y: 9), Layer(grid: dot, x: 21, y: 2), Layer(grid: dot, x: 2, y: 12)]
                : [Layer(grid: sparkle, x: 20, y: 1), Layer(grid: sparkle, x: 0, y: 10), Layer(grid: dot, x: 3, y: 1), Layer(grid: dot, x: 22, y: 13)]
            frames.append(frame(dy: dy, face: faceExcited, free: sparkles, wideShadow: dy > -2))
        }
        return PetAnimation(fps: 8, frames: frames)
    }()
}

func cgColor(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}
