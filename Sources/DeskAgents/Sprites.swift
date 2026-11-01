import AppKit

/// Everything that changes how an agent looks, quantised so a view only
/// redraws when the picture actually changes.
struct Pose: Equatable {
    var seated = false
    var sleeping = false
    var dangling = false
    var walking = false
    var step = 0            // which legs are lifted
    var blink = false
    var look = 0            // -1 left, 0 at you, 1 right
    var waving = false
    var waveUp = false
    var thinkingFrame = -1  // -1 when not thinking
    var unread = false
    var zFrame = 0
    var cursorOn = true

    init(_ a: Agent, now: TimeInterval) {
        seated = a.activity == .sitting || a.activity == .sleeping
        sleeping = a.activity == .sleeping
        dangling = a.activity == .dragged
        walking = a.isWalking && !a.isHovered && !a.isAirborne
        if walking || dangling { step = Int(a.walkPhase / .pi) & 1 }
        blink = a.isBlinking
        let facingYou = a.isHovered || a.activity == .listening
        look = facingYou ? 0 : (a.facing > 0 ? 1 : -1)
        waving = a.isSpeaking
        if waving { waveUp = Int(now * 4) % 2 == 0 }
        thinkingFrame = a.isThinking ? Int(now * 3) % 3 : -1
        unread = a.hasUnread
        if sleeping { zFrame = Int(now * 1.5) % 2 }
        cursorOn = waving ? waveUp : (facingYou || Int(now / 0.55) % 2 == 0)
    }
}

extension AgentKind {
    var spriteSize: NSSize {
        switch self {
        case .claude: return ClaudeArt.size
        case .codex: return CodexArt.size
        }
    }

    /// Used for the little marks (zZ) drawn next to the sprite.
    var accent: NSColor {
        switch self {
        case .claude: return NSColor(cgColor: ClaudeArt.body)!
        case .codex: return NSColor(srgbRed: 0.43, green: 0.61, blue: 0.97, alpha: 1)
        }
    }
}

/// Claude's pixel critter: a wide terracotta body, two tall eyes, side nubs
/// and four little legs. Laid out on a 56 x 35 grid, flipped coordinates.
enum ClaudeArt {
    static let unit: CGFloat = 1.5
    static let size = NSSize(width: 56 * unit, height: 35 * unit)
    static let body = CGColor(srgbRed: 0.80, green: 0.47, blue: 0.36, alpha: 1)  // #CC785C
    private static let eye = CGColor(gray: 0, alpha: 1)

    static func draw(_ pose: Pose, in box: NSRect, ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.translateBy(x: box.minX, y: box.minY)
        ctx.scaleBy(x: unit, y: unit)

        let legHeight: CGFloat = 7
        let bx: CGFloat = 7
        let by: CGFloat = pose.seated ? legHeight : 0

        ctx.setFillColor(body)
        if !pose.seated {
            for (i, lx) in [3, 9, 29, 35].enumerated() {
                var h = legHeight
                if pose.walking && i % 2 == pose.step { h -= 2 }
                if pose.dangling { h += i % 2 == pose.step ? 1 : -1 }
                ctx.fill(CGRect(x: bx + CGFloat(lx), y: by + 28, width: 4, height: h))
            }
        }
        ctx.fill(CGRect(x: bx, y: by, width: 42, height: 28))

        var leftArm = by + 14, rightArm = by + 14
        if pose.dangling {
            leftArm -= 7
            rightArm -= 7
        } else if pose.waving {
            let lift: CGFloat = pose.waveUp ? 9 : 6
            if pose.look >= 0 { rightArm -= lift } else { leftArm -= lift }
        }
        ctx.fill(CGRect(x: bx - 7, y: leftArm, width: 7, height: 7))
        ctx.fill(CGRect(x: bx + 42, y: rightArm, width: 7, height: 7))

        ctx.setFillColor(eye)
        let shift = CGFloat(pose.look * 2)
        let closed = pose.blink || pose.sleeping
        let eyeY = by + (closed ? 12 : 8)
        let eyeHeight: CGFloat = closed ? 2 : 6
        ctx.fill(CGRect(x: bx + 8 + shift, y: eyeY, width: 2, height: eyeHeight))
        ctx.fill(CGRect(x: bx + 32 + shift, y: eyeY, width: 2, height: eyeHeight))
    }

    /// Top of the drawn body, for placing marks above it.
    static func top(_ pose: Pose, in box: NSRect) -> CGFloat {
        box.minY + (pose.seated ? 7 * unit : 0)
    }
}

/// Codex's blue cloud-headed bot with a terminal for a face, as a pixel grid.
enum CodexArt {
    static let pixel: CGFloat = 2
    private static let grid: [[UInt8]] = [
        "...........KKKKK..KKKK.........",
        ".........KKHHLLLKKLLLLK........",
        "........KHLLLLLLLLLLLLLK.......",
        ".......KHLLLLLLLLLLLLLLLK......",
        "......KLLLLLLLLLLLLLLLLLLK.....",
        "......KLLLLLLLLLLLLLLLLLLK.....",
        "....KKMLLLLLLLLLLLLLLLLLLLK....",
        "...KMLLLLLLLLLLLLLLLLLLLLLLK...",
        "..KMLLLLLLLLLLLLLLLLLLLLLLLLK..",
        ".KMLLLLLLLLLLLLLLLLLLLLLLLLLLK.",
        ".KMMLLLLLKNNNNNNNNNNNNNKLLLLLK.",
        "KMMMLLLLKNNNNNNNNNNNNNNNKLLLLLK",
        "KMMMLLLLKNNNNNNNNNNNNNNNKLLLLLK",
        "KMMMLLLLKNNNNNNNNNNNNNNNKLLLLLK",
        "KMMMMMLLKNNNNNNNNNNNNNNNKLLLLMK",
        "KMMMMMMLKNNNNNNNNNNNNNNNKLLLMMK",
        "KDMMMMMLKNNNNNNNNNNNNNNNKLLMMMK",
        "KDMMMMMLKNNNNNNNNNNNNNNNKLMMMMK",
        ".KDMMMMLKNNNNNNNNNNNNNNNKMMMMK.",
        ".KDMMMMMKNNNNNNNNNNNNNNNKMMMMK.",
        "..KDMMMMMKNNNNNNNNNNNNNKMMMMK..",
        "..KDDMMMMMKKKKKKKKKKKKKMMMMDK..",
        "...KKDMMMMMMMMMMMMMMMMMMMDKK...",
        ".....KKKDDDDDDDDDDDDDDDDKKK....",
        ".......KKKKKKKKKKKKKKKKKK......",
        "....KK.KDMMMMMMMMMMMMMLMK.KK...",
        "...KMMKKDMMMMMMMLLLLLLLMKKMMK..",
        "...KMMMKDMMMMMMMLLLLLLLMKMMLK..",
        "...KMMMKDMMMMMMMMMMMMMMMKMMLK..",
        "...KDMMKDDMMMMMMMMMMMMMMKMMMK..",
        "....KKKKDDDMMMMMMMMMMMMMKKKK...",
        ".......KKDDDDDDDDDDDDDDKK......",
        ".........KDDDMK.KMMMDK.........",
        ".........KMMMMK.KMMMMK.........",
        ".........KMMMMK.KMMMMK.........",
        ".........KKKKKK.KKKKKK.........",
    ].map { Array($0.utf8) }

    static let size = NSSize(width: CGFloat(grid[0].count) * pixel, height: CGFloat(grid.count) * pixel)

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
        CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    private static let palette: [UInt8: CGColor] = [
        UInt8(ascii: "K"): rgb(22, 32, 84),
        UInt8(ascii: "L"): rgb(110, 155, 248),
        UInt8(ascii: "M"): rgb(80, 122, 236),
        UInt8(ascii: "D"): rgb(58, 90, 204),
        UInt8(ascii: "N"): rgb(31, 42, 94),
        UInt8(ascii: "H"): rgb(160, 195, 255),
    ]
    private static let glyph = rgb(195, 248, 255)
    private static let glyphDim = rgb(80, 100, 170)

    private static let prompt = [(11, 13), (12, 13), (12, 14), (13, 14), (13, 15), (14, 15), (12, 16), (13, 16), (11, 17), (12, 17)]
    private static let cursor = [(17, 17), (18, 17), (19, 17), (20, 17), (21, 17)]
    private static let asleep = [(11, 15), (12, 15), (13, 15), (18, 15), (19, 15), (20, 15)]
    private static let chest = [(11, 27), (12, 28), (11, 29), (14, 29), (15, 29), (16, 29)]

    static func draw(_ pose: Pose, in box: NSRect, ctx: CGContext) {
        let drop = pose.seated ? 4 : 0  // legs tucked under

        if !pose.seated {
            var left = 0, right = 0
            if pose.walking { if pose.step == 0 { left = -1 } else { right = -1 } }
            if pose.dangling { left = pose.step == 0 ? 1 : 0; right = 1 - left }
            fill(ctx, box, rows: 32...35, cols: 0...15, dy: left)
            fill(ctx, box, rows: 32...35, cols: 16...30, dy: right)
        }
        fill(ctx, box, rows: 24...31, cols: 7...24, dy: drop)

        var leftArm = 0, rightArm = 0
        if pose.dangling {
            leftArm = -3
            rightArm = -3
        } else if pose.waving {
            let lift = pose.waveUp ? -3 : -2
            if pose.look >= 0 { rightArm = lift } else { leftArm = lift }
        }
        fill(ctx, box, rows: 25...31, cols: 0...6, dy: drop + leftArm)
        fill(ctx, box, rows: 25...31, cols: 25...30, dy: drop + rightArm)
        fill(ctx, box, rows: 0...23, cols: 0...30, dy: drop)

        // The screen face
        let dx = pose.look
        if pose.thinkingFrame >= 0 {
            for i in 0..<3 {
                ctx.setFillColor(i == pose.thinkingFrame ? glyph : glyphDim)
                for (c, r) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                    cell(ctx, box, col: 11 + i * 4 + c + dx, row: 15 + r + drop)
                }
            }
        } else {
            ctx.setFillColor(glyph)
            let face = pose.sleeping ? asleep : prompt + (pose.cursorOn ? cursor : [])
            for (c, r) in face { cell(ctx, box, col: c + dx, row: r + drop) }
        }
        ctx.setFillColor(glyph)
        for (c, r) in chest { cell(ctx, box, col: c, row: r + drop) }
    }

    static func top(_ pose: Pose, in box: NSRect) -> CGFloat {
        box.minY + CGFloat(pose.seated ? 4 : 0) * pixel
    }

    private static func cell(_ ctx: CGContext, _ box: NSRect, col: Int, row: Int) {
        ctx.fill(CGRect(x: box.minX + CGFloat(col) * pixel, y: box.minY + CGFloat(row) * pixel, width: pixel, height: pixel))
    }

    /// Fills grid cells, merging runs of the same colour into one rectangle.
    private static func fill(_ ctx: CGContext, _ box: NSRect, rows: ClosedRange<Int>, cols: ClosedRange<Int>, dy: Int) {
        for r in rows {
            let line = grid[r]
            var c = cols.lowerBound
            while c <= cols.upperBound {
                let ch = line[c]
                guard let color = palette[ch] else {
                    c += 1
                    continue
                }
                var end = c
                while end < cols.upperBound && line[end + 1] == ch { end += 1 }
                ctx.setFillColor(color)
                ctx.fill(CGRect(x: box.minX + CGFloat(c) * pixel, y: box.minY + CGFloat(r + dy) * pixel,
                                width: CGFloat(end - c + 1) * pixel, height: pixel))
                c = end + 1
            }
        }
    }
}
