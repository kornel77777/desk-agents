import AppKit

enum AgentKind: String, CaseIterable {
    case claude, codex

    var name: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    /// Shown in the chat header so it's clear which tool is answering.
    var command: String {
        switch self {
        case .claude: return "claude -p"
        case .codex: return "codex exec"
        }
    }

    var walkSpeed: CGFloat {
        switch self {
        case .claude: return 34
        case .codex: return 40
        }
    }
}

enum Activity: Equatable {
    case idle
    case walking(to: CGFloat)
    case sitting
    case sleeping
    case talking    // small talk with another agent
    case listening  // chat panel is open
    case dragged
}

/// One wandering character. Positions are in stage coordinates: `x` is the
/// centre of the feet, `y` is the height above the ground line.
final class Agent {
    static let gravity: CGFloat = 1100

    let kind: AgentKind
    let view: AgentView

    var x: CGFloat
    var y: CGFloat = 0
    var vx: CGFloat = 0
    var vy: CGFloat = 0
    var facing: CGFloat = 1
    var activity: Activity = .idle
    var activityEnds: TimeInterval = 0
    var walkPhase: CGFloat = 0

    var isSpeaking = false
    var isThinking = false
    var isHovered = false
    var hasUnread = false
    var lastChat: [AgentKind: TimeInterval] = [:]

    private var blinkEnds: TimeInterval = 0
    private var nextBlink: TimeInterval = 0

    init(kind: AgentKind, x: CGFloat) {
        self.kind = kind
        self.x = x
        view = AgentView(kind: kind)
        view.agent = self
    }

    var isAirborne: Bool { y > 0 || vy != 0 }
    var isBlinking: Bool { CACurrentMediaTime() < blinkEnds }

    var isWalking: Bool {
        if case .walking = activity { return true }
        return false
    }

    /// Free to be pulled into small talk.
    var isFree: Bool { !isAirborne && !isThinking && (activity == .idle || isWalking) }

    func setActivity(_ new: Activity, for duration: TimeInterval, now: TimeInterval) {
        activity = new
        activityEnds = now + duration
    }

    func walk(to target: CGFloat, minX: CGFloat, maxX: CGFloat, now: TimeInterval) {
        let clamped = min(max(target, minX), maxX)
        if abs(clamped - x) < 8 {
            setActivity(.idle, for: 1, now: now)
        } else {
            activity = .walking(to: clamped)
        }
    }

    func update(dt: CGFloat, now: TimeInterval, minX: CGFloat, maxX: CGFloat, others: [Agent]) {
        if now >= nextBlink {
            blinkEnds = now + 0.13
            nextBlink = now + .random(in: 2.5...6)
        }

        if activity == .dragged {
            walkPhase += dt * 22
            return
        }

        if isAirborne {
            vy -= Agent.gravity * dt
            y += vy * dt
            x += vx * dt
            if x < minX { x = minX; vx = abs(vx) * 0.5 }
            if x > maxX { x = maxX; vx = -abs(vx) * 0.5 }
            if y <= 0 {
                let impact = -vy
                y = 0
                vy = 0
                vx = 0
                if impact > 900 && activity == .idle {
                    setActivity(.sitting, for: 1.8, now: now)  // a little dazed
                }
            }
            return
        }

        x = min(max(x, minX), maxX)

        switch activity {
        case .idle:
            if !isHovered, let crowd = others.first(where: { !$0.isAirborne && $0.activity != .dragged && abs($0.x - x) < 76 }) {
                // Personal space: step aside rather than stand inside someone.
                let away: CGFloat = x != crowd.x ? (x > crowd.x ? 1 : -1) : (kind.rawValue < crowd.kind.rawValue ? -1 : 1)
                walk(to: x + away * 84, minX: minX, maxX: maxX, now: now)
            } else if now >= activityEnds {
                decide(now: now, minX: minX, maxX: maxX, others: others)
            }
        case .walking(let target):
            guard !isHovered else { return }  // stops to look at you
            let dir: CGFloat = target >= x ? 1 : -1
            facing = dir
            let step = kind.walkSpeed * dt
            if abs(target - x) <= step {
                x = target
                setActivity(.idle, for: .random(in: 1.2...4.5), now: now)
            } else {
                x += dir * step
                walkPhase += dt * kind.walkSpeed / 4.2
            }
        case .sitting, .sleeping:
            if now >= activityEnds { setActivity(.idle, for: .random(in: 0.6...2), now: now) }
        case .talking, .listening, .dragged:
            break
        }
    }

    private func decide(now: TimeInterval, minX: CGFloat, maxX: CGFloat, others: [Agent]) {
        let roll = Double.random(in: 0..<1)
        if roll < 0.22, let friend = others.randomElement() {
            let side: CGFloat = friend.x > x ? -1 : 1
            walk(to: friend.x + side * 92, minX: minX, maxX: maxX, now: now)
        } else if roll < 0.62 {
            walk(to: x + .random(in: -420...420), minX: minX, maxX: maxX, now: now)
        } else if roll < 0.72 {
            vy = .random(in: 190...240)  // hop
            setActivity(.idle, for: .random(in: 0.8...2), now: now)
        } else if roll < 0.84 || isThinking {
            setActivity(.sitting, for: .random(in: 4...10), now: now)
        } else if roll < 0.90 {
            setActivity(.sleeping, for: .random(in: 10...22), now: now)
        } else {
            facing = -facing
            setActivity(.idle, for: .random(in: 1.5...4), now: now)
        }
    }
}
