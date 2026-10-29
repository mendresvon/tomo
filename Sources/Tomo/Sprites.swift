import SwiftUI

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

    static let palette: [Character: Color] = [
        "K": Color(hex: 0x3D2333),  // outline
        "R": Color(hex: 0xFF5B5B),  // body
        "D": Color(hex: 0xD93F4C),  // body shade
        "H": Color(hex: 0xFFA8A0),  // body highlight
        "G": Color(hex: 0x5CC96B),  // leaf
        "g": Color(hex: 0x2F8F4E),  // leaf shade and stem
        "k": Color(hex: 0x2A1620),  // eyes and mouth
        "W": Color(hex: 0xFFFFFF),  // eye shine
        "P": Color(hex: 0xFF8FAB),  // cheeks
        "B": Color(hex: 0x4D9DE0),  // headband
        "L": Color(hex: 0xC3CCDA),  // laptop lid
        "l": Color(hex: 0xFFFFFF),  // laptop logo
        "A": Color(hex: 0x8592A8),  // laptop base
        "T": Color(hex: 0xC9824A),  // tea
        "M": Color(hex: 0xFFF4E2),  // mug
        "s": Color(hex: 0xB8C4D6),  // steam
        "z": Color(hex: 0x7FA7FF),  // sleep Z
        "Y": Color(hex: 0xFFD23F),  // sparkle
        "S": Color.black.opacity(0.18),  // ground shadow
    ]

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

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
