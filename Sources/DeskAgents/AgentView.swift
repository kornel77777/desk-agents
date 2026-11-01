import AppKit

protocol AgentViewDelegate: AnyObject {
    func agentPressed(_ agent: Agent, at point: NSPoint)
    func agentDragged(_ agent: Agent, to point: NSPoint)
    func agentReleased(_ agent: Agent, at point: NSPoint)
    func agentMenuRequested(_ agent: Agent, with event: NSEvent)
}

/// Draws one agent's pixel sprite. Feet sit on the bottom edge of the view;
/// the space above the sprite holds status marks.
final class AgentView: NSView {
    private static let headroom: CGFloat = 14
    private static let sideRoom: CGFloat = 8

    let kind: AgentKind
    weak var agent: Agent?
    weak var delegate: AgentViewDelegate?
    private var pose: Pose?

    init(kind: AgentKind) {
        self.kind = kind
        let s = kind.spriteSize
        super.init(frame: NSRect(x: 0, y: 0, width: s.width + Self.sideRoom * 2, height: s.height + Self.headroom))
        wantsLayer = true
        let shade = NSShadow()
        shade.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shade.shadowBlurRadius = 2
        shade.shadowOffset = NSSize(width: 0, height: -1)
        shadow = shade
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var spriteBox: NSRect {
        NSRect(origin: NSPoint(x: Self.sideRoom, y: Self.headroom), size: kind.spriteSize)
    }

    /// The clickable part, in the stage's coordinates: the sprite only.
    var hitRect: NSRect {
        NSRect(x: frame.minX + Self.sideRoom, y: frame.minY, width: kind.spriteSize.width, height: kind.spriteSize.height)
    }

    /// Redraws only when the pose changed since the last frame.
    func refresh(now: TimeInterval) {
        guard let agent else { return }
        let next = Pose(agent, now: now)
        if next != pose {
            pose = next
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let agent else { return }
        if event.modifierFlags.contains(.control) {
            delegate?.agentMenuRequested(agent, with: event)
        } else {
            delegate?.agentPressed(agent, at: event.locationInWindow)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if let agent { delegate?.agentMenuRequested(agent, with: event) }
    }

    override func mouseDragged(with event: NSEvent) {
        if let agent { delegate?.agentDragged(agent, to: event.locationInWindow) }
    }

    override func mouseUp(with event: NSEvent) {
        if let agent { delegate?.agentReleased(agent, at: event.locationInWindow) }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let pose, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let box = spriteBox
        ctx.setShouldAntialias(false)
        let top: CGFloat
        switch kind {
        case .claude:
            ClaudeArt.draw(pose, in: box, ctx: ctx)
            top = ClaudeArt.top(pose, in: box)
        case .codex:
            CodexArt.draw(pose, in: box, ctx: ctx)
            top = CodexArt.top(pose, in: box)
        }

        // One status mark at a time, just above the head.
        if pose.thinkingFrame >= 0 && kind == .claude {
            // (Codex shows thinking on its screen instead.)
            for i in 0..<3 {
                let s: CGFloat = i == pose.thinkingFrame ? 3 : 2
                ctx.setFillColor(NSColor(white: 0.1, alpha: 1).cgColor)
                ctx.fill(CGRect(x: box.midX - 6 + CGFloat(i) * 5 - s / 2, y: top - 6 - s / 2, width: s, height: s))
            }
        } else if pose.unread {
            ctx.setShouldAntialias(true)
            let c = CGPoint(x: box.maxX - 4, y: top - 5)
            ctx.setFillColor(NSColor(white: 0.07, alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10))
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: c.x - 0.75, y: c.y - 3, width: 1.5, height: 3.5))
            ctx.fill(CGRect(x: c.x - 0.75, y: c.y + 1.5, width: 1.5, height: 1.5))
        } else if pose.sleeping {
            ctx.setShouldAntialias(true)
            let lift = CGFloat(pose.zFrame)
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9, weight: .heavy), .foregroundColor: kind.accent]
            ("z" as NSString).draw(at: NSPoint(x: box.maxX - 12, y: top - 11 - lift), withAttributes: attrs)
            ("z" as NSString).draw(at: NSPoint(x: box.maxX - 6, y: top - 15 - lift),
                                   withAttributes: attrs.merging([.font: NSFont.systemFont(ofSize: 7, weight: .heavy)]) { $1 })
        }
    }
}

/// Small black pill with the agent's name, shown on hover.
final class NameTagView: NSView {
    private static let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor.white,
    ]

    var text = "" { didSet { if text != oldValue { needsDisplay = true } } }

    var idealSize: NSSize {
        let s = (text as NSString).size(withAttributes: Self.attrs)
        return NSSize(width: ceil(s.width) + 14, height: 18)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.07, alpha: 0.9).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
        let s = (text as NSString).size(withAttributes: Self.attrs)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - s.width) / 2, y: (bounds.height - s.height) / 2),
                                withAttributes: Self.attrs)
    }
}

/// Comic-style speech bubble with a tail pointing down at the speaker.
final class SpeechBubbleView: NSView {
    private static let tail: CGFloat = 6
    private static let maxTextWidth: CGFloat = 190
    private static let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12),
        .foregroundColor: NSColor(white: 0.07, alpha: 1),
    ]

    var text = "" { didSet { if text != oldValue { needsDisplay = true } } }
    var tailX: CGFloat = 0 { didSet { if tailX != oldValue { needsDisplay = true } } }

    override var isFlipped: Bool { false }

    var idealSize: NSSize {
        let r = (text as NSString).boundingRect(with: NSSize(width: Self.maxTextWidth, height: 400),
                                                options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                attributes: Self.attrs)
        return NSSize(width: ceil(r.width) + 20, height: ceil(r.height) + 12 + Self.tail)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let t = Self.tail, r: CGFloat = 9
        let minX: CGFloat = 0.75, maxX = bounds.width - 0.75, minY = t, maxY = bounds.height - 0.75
        let tip = min(max(tailX, minX + r + 6), maxX - r - 6)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: tip + 5, y: minY))
        path.addLine(to: CGPoint(x: maxX - r, y: minY))
        path.addArc(tangent1End: CGPoint(x: maxX, y: minY), tangent2End: CGPoint(x: maxX, y: minY + r), radius: r)
        path.addLine(to: CGPoint(x: maxX, y: maxY - r))
        path.addArc(tangent1End: CGPoint(x: maxX, y: maxY), tangent2End: CGPoint(x: maxX - r, y: maxY), radius: r)
        path.addLine(to: CGPoint(x: minX + r, y: maxY))
        path.addArc(tangent1End: CGPoint(x: minX, y: maxY), tangent2End: CGPoint(x: minX, y: maxY - r), radius: r)
        path.addLine(to: CGPoint(x: minX, y: minY + r))
        path.addArc(tangent1End: CGPoint(x: minX, y: minY), tangent2End: CGPoint(x: minX + r, y: minY), radius: r)
        path.addLine(to: CGPoint(x: tip - 5, y: minY))
        path.addLine(to: CGPoint(x: tip, y: 0.75))
        path.closeSubpath()

        ctx.setFillColor(NSColor.white.cgColor)
        ctx.setStrokeColor(NSColor(white: 0.07, alpha: 1).cgColor)
        ctx.setLineWidth(1.3)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.drawPath(using: .fillStroke)

        (text as NSString).draw(in: NSRect(x: 10, y: t + 6, width: bounds.width - 20, height: bounds.height - t - 12),
                                withAttributes: Self.attrs)
    }
}
