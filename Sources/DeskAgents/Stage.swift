import AppKit

enum Placement: String {
    case desktop  // just above the wallpaper, behind every app window
    case top      // floats above all windows
}

final class StageWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Transparent full-screen view; only the agents themselves take clicks.
final class StageView: NSView {
    override var isFlipped: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        for case let view as AgentView in subviews.reversed() where view.hitRect.contains(p) {
            return view
        }
        return nil
    }
}

private final class Exchange {
    let a: Agent  // walked up and speaks first
    let b: Agent
    let startedAt: TimeInterval
    var lines: [(speaker: Agent, text: String)] = []
    var index = -1
    var lineEnds: TimeInterval = 0
    var pending = false  // waiting on real lines from the CLIs

    init(a: Agent, b: Agent, now: TimeInterval) {
        self.a = a
        self.b = b
        startedAt = now
    }
}

/// Owns the overlay window, runs the animation loop and handles clicks,
/// drags and small talk.
final class Stage: NSObject, AgentViewDelegate {
    private struct Press {
        let agent: Agent
        let start: NSPoint
        let grab: CGVector
        var dragging = false
        var samples: [(time: TimeInterval, point: NSPoint)] = []
    }

    var placement: Placement = .desktop { didSet { applyPlacement() } }
    var liveChatter = false
    /// The app menu, also shown on right-click in case the menu-bar icon is
    /// hidden behind the notch.
    var menuProvider: (() -> NSMenu)?

    private let window = StageWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    private let stageView = StageView()
    private let bubble = SpeechBubbleView()
    private let nameTag = NameTagView()
    private let chat = ChatController()
    private(set) var agents: [Agent] = []

    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var bubbleOwner: Agent?
    private var exchange: Exchange?
    private var lastExchangeEnded: TimeInterval = 0
    private var lastLiveChatter: TimeInterval = -.infinity
    private var bubbleEnds: TimeInterval = 0  // for one-off lines outside a conversation
    private var nextQuip = CACurrentMediaTime() + .random(in: 8...15)
    private var press: Press?
    private var minX: CGFloat = 0
    private var maxX: CGFloat = 0
    private var groundY: CGFloat = 0

    override init() {
        super.init()
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        stageView.wantsLayer = true
        window.contentView = stageView

        bubble.wantsLayer = true
        bubble.isHidden = true
        nameTag.wantsLayer = true
        nameTag.isHidden = true
        stageView.addSubview(bubble)
        stageView.addSubview(nameTag)

        chat.onClose = { [weak self] agent in self?.chatClosed(agent) }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        fitToScreen()
        applyPlacement()
    }

    func start() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        window.orderFrontRegardless()
    }

    func setEnabled(_ kinds: [AgentKind]) {
        for agent in agents where !kinds.contains(agent.kind) { remove(agent) }
        for (i, kind) in kinds.enumerated() where !agents.contains(where: { $0.kind == kind }) {
            let span = maxX - minX
            let x = minX + span * CGFloat(i + 1) / CGFloat(kinds.count + 1) + .random(in: -60...60)
            let agent = Agent(kind: kind, x: x)
            agent.y = window.frame.height * 0.3 + CGFloat(i) * 50  // drop in from above
            agent.view.delegate = self
            stageView.addSubview(agent.view, positioned: .below, relativeTo: bubble)
            agents.append(agent)
        }
    }

    /// Everyone walks over to the mouse pointer.
    func callOver() {
        let now = CACurrentMediaTime()
        if let exchange { finish(exchange, now: now) }
        let mouseX = NSEvent.mouseLocation.x - window.frame.minX
        for (i, agent) in agents.enumerated() where agent.activity != .listening && agent.activity != .dragged {
            let offset = (CGFloat(i) - CGFloat(agents.count - 1) / 2) * 96
            agent.walk(to: mouseX + offset, minX: minX, maxX: maxX, now: now)
        }
    }

    // MARK: - Window

    @objc private func screensChanged() { fitToScreen() }

    private func fitToScreen() {
        guard let screen = NSScreen.screens.first else { return }
        let f = screen.frame, v = screen.visibleFrame
        window.setFrame(f, display: true)
        groundY = v.minY - f.minY
        minX = v.minX - f.minX + 46
        maxX = v.maxX - f.minX - 46
    }

    private func applyPlacement() {
        switch placement {
        case .desktop:
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        case .top:
            window.level = .floating
        }
        window.orderFrontRegardless()
    }

    private func remove(_ agent: Agent) {
        if chat.isOpen(for: agent) { chat.close() }
        if let exchange, exchange.a === agent || exchange.b === agent { finish(exchange, now: CACurrentMediaTime()) }
        if press?.agent === agent { press = nil }
        agent.view.removeFromSuperview()
        agents.removeAll { $0 === agent }
    }

    // MARK: - Loop

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(now - lastTick, 0.05))
        lastTick = now

        updateHover()
        for agent in agents {
            agent.update(dt: dt, now: now, minX: minX, maxX: maxX, others: agents.filter { $0 !== agent })
        }
        if let exchange {
            advance(exchange, now: now)
        } else {
            if bubbleOwner != nil && now >= bubbleEnds { hush() }
            maybeStartExchange(now: now)
            maybeQuip(now: now)
        }
        for agent in agents where agent.landedHard {
            agent.landedHard = false
            blurt(agent, Chatter.landedLine(), now: now)
        }
        layoutViews()
    }

    /// The window ignores the mouse except while the pointer is over an agent,
    /// so the rest of the desktop keeps working normally.
    private func updateHover() {
        let mouse = NSEvent.mouseLocation
        let p = NSPoint(x: mouse.x - window.frame.minX, y: mouse.y - window.frame.minY)
        let hovered = press?.agent ?? agents.last(where: { $0.view.hitRect.contains(p) })
        for agent in agents { agent.isHovered = agent === hovered && press?.dragging != true }
        let ignore = hovered == nil
        if window.ignoresMouseEvents != ignore { window.ignoresMouseEvents = ignore }
    }

    private func layoutViews() {
        let now = CACurrentMediaTime()
        for agent in agents {
            let size = agent.view.frame.size
            agent.view.setFrameOrigin(NSPoint(x: halfPoint(agent.x - size.width / 2), y: halfPoint(groundY + agent.y)))
            agent.view.refresh(now: now)
        }

        if let owner = bubbleOwner, !bubble.isHidden {
            let s = bubble.idealSize
            let anchor = owner.view.frame
            let x = min(max(anchor.midX - s.width / 2, 8), stageView.bounds.width - s.width - 8)
            bubble.frame = NSRect(x: halfPoint(x), y: halfPoint(anchor.maxY - 2), width: s.width, height: s.height)
            bubble.tailX = anchor.midX - bubble.frame.minX
        }

        // Name tag only when no bubble is up, so text never overlaps.
        if let hovered = agents.first(where: { $0.isHovered }), bubble.isHidden, !chat.isOpen(for: hovered) {
            nameTag.text = hovered.kind.name
            let s = nameTag.idealSize
            let anchor = hovered.view.frame
            nameTag.frame = NSRect(x: halfPoint(anchor.midX - s.width / 2), y: halfPoint(anchor.maxY - 2),
                                   width: s.width, height: s.height)
            nameTag.isHidden = false
        } else {
            nameTag.isHidden = true
        }
    }

    private func halfPoint(_ v: CGFloat) -> CGFloat { (v * 2).rounded() / 2 }

    // MARK: - Small talk

    private func say(_ agent: Agent, _ text: String) {
        if bubbleOwner === agent && bubble.text == text && !bubble.isHidden { return }
        for other in agents { other.isSpeaking = other === agent && text != "…" }
        bubbleOwner = agent
        bubble.text = text
        bubble.isHidden = false
    }

    private func hush() {
        bubble.isHidden = true
        bubbleOwner = nil
        for agent in agents { agent.isSpeaking = false }
    }

    /// A one-off line outside a conversation.
    private func blurt(_ agent: Agent, _ text: String, now: TimeInterval) {
        guard exchange == nil, !chat.isOpen else { return }
        say(agent, text)
        bubbleEnds = now + max(2.4, 1.0 + Double(text.count) * 0.065)
    }

    /// Every so often one of them mutters something to nobody in particular.
    private func maybeQuip(now: TimeInterval) {
        guard now >= nextQuip else { return }
        nextQuip = now + .random(in: 18...40)
        let candidates = agents.filter { !$0.isAirborne && $0.activity != .dragged && $0.activity != .listening }
        guard bubble.isHidden, !chat.isOpen, press == nil, let agent = candidates.randomElement() else { return }
        blurt(agent, Chatter.quip(for: agent.kind, asleep: agent.activity == .sleeping), now: now)
    }

    private func maybeStartExchange(now: TimeInterval) {
        guard !chat.isOpen, press == nil, bubble.isHidden, now - lastExchangeEnded > 14 else { return }
        for (i, a) in agents.enumerated() {
            for b in agents[(i + 1)...] {
                guard a.isFree, b.isFree, !a.isHovered, !b.isHovered else { continue }
                let gap = abs(a.x - b.x)
                guard gap > 80, gap < 110 else { continue }
                guard now - (a.lastChat[b.kind] ?? -.infinity) > 70 else { continue }
                begin(first: a.isWalking ? a : b, second: a.isWalking ? b : a, now: now)
                return
            }
        }
    }

    private func begin(first: Agent, second: Agent, now: TimeInterval) {
        let ex = Exchange(a: first, b: second, now: now)
        for (me, other) in [(first, second), (second, first)] {
            me.activity = .talking
            me.facing = other.x > me.x ? 1 : -1
        }
        exchange = ex
        if liveChatter && now - lastLiveChatter > 240 {
            lastLiveChatter = now
            ex.pending = true
            talkForReal(ex)
        } else {
            ex.lines = cannedLines(ex)
        }
    }

    private func advance(_ ex: Exchange, now: TimeInterval) {
        guard ex.a.activity == .talking, ex.b.activity == .talking else {
            finish(ex, now: now)
            return
        }
        if ex.pending && now - ex.startedAt > 30 {
            ex.pending = false
            if ex.lines.isEmpty { ex.lines = cannedLines(ex) }
        }
        guard now >= ex.lineEnds else { return }
        if ex.index + 1 < ex.lines.count {
            ex.index += 1
            let line = ex.lines[ex.index]
            say(line.speaker, line.text)
            ex.lineEnds = now + max(2.2, 1.0 + Double(line.text.count) * 0.065)
        } else if ex.pending {
            if ex.index < 0 { say(ex.a, "…") }
        } else {
            finish(ex, now: now)
        }
    }

    private func finish(_ ex: Exchange, now: TimeInterval) {
        guard exchange === ex else { return }
        exchange = nil
        lastExchangeEnded = now
        hush()
        for (me, other) in [(ex.a, ex.b), (ex.b, ex.a)] {
            me.lastChat[other.kind] = now
            if me.activity == .talking { me.setActivity(.idle, for: .random(in: 0.5...1.8), now: now) }
        }
    }

    private func cannedLines(_ ex: Exchange) -> [(speaker: Agent, text: String)] {
        Chatter.script(ex.a.kind, ex.b.kind).map { (speaker: $0.0 == ex.a.kind ? ex.a : ex.b, text: $0.1) }
    }

    /// One real line each from the two CLIs; falls back to canned lines.
    private func talkForReal(_ ex: Exchange) {
        let a = ex.a, b = ex.b
        AgentCLI.ask(a.kind, prompt: Chatter.openerPrompt(from: a.kind, to: b.kind), timeout: 40) { [weak self] first in
            guard let self, self.exchange === ex, ex.pending else { return }
            guard let line = (try? first.get()).flatMap(Chatter.tidy) else {
                ex.lines = self.cannedLines(ex)
                ex.pending = false
                return
            }
            ex.lines.append((speaker: a, text: line))
            AgentCLI.ask(b.kind, prompt: Chatter.replyPrompt(from: b.kind, to: a.kind, heard: line), timeout: 40) { [weak self] second in
                guard let self, self.exchange === ex, ex.pending else { return }
                if let reply = (try? second.get()).flatMap(Chatter.tidy) {
                    ex.lines.append((speaker: b, text: reply))
                }
                ex.pending = false
            }
        }
    }

    // MARK: - Mouse

    func agentPressed(_ agent: Agent, at point: NSPoint) {
        press = Press(agent: agent, start: point,
                      grab: CGVector(dx: point.x - agent.x, dy: point.y - (groundY + agent.y)))
    }

    func agentDragged(_ agent: Agent, to point: NSPoint) {
        guard var p = press, p.agent === agent else { return }
        let now = CACurrentMediaTime()
        if !p.dragging {
            guard hypot(point.x - p.start.x, point.y - p.start.y) > 4 else { return }
            p.dragging = true
            if chat.isOpen(for: agent) { chat.close() }
            if let exchange, exchange.a === agent || exchange.b === agent { finish(exchange, now: now) }
            agent.activity = .dragged
            agent.vx = 0
            agent.vy = 0
            if Double.random(in: 0..<1) < 0.6 { blurt(agent, Chatter.pickedUpLine(), now: now) }
        }
        agent.x = point.x - p.grab.dx
        agent.y = max(0, point.y - p.grab.dy - groundY)
        p.samples.append((time: now, point: point))
        p.samples.removeAll { now - $0.time > 0.1 }
        press = p
    }

    func agentReleased(_ agent: Agent, at point: NSPoint) {
        guard let p = press, p.agent === agent else { return }
        press = nil
        let now = CACurrentMediaTime()
        guard p.dragging else {
            clicked(agent, now: now)
            return
        }
        // Throw with the speed of the last few drag samples.
        if let first = p.samples.first, let last = p.samples.last, last.time - first.time > 0.01 {
            let t = CGFloat(last.time - first.time)
            agent.vx = min(max((last.point.x - first.point.x) / t, -1400), 1400)
            agent.vy = min(max((last.point.y - first.point.y) / t, -1400), 1400)
        }
        if agent.y <= 0 && agent.vy <= 0 {
            agent.vx = 0
            agent.vy = 0
        }
        agent.setActivity(.idle, for: .random(in: 0.8...2), now: now)
    }

    func agentMenuRequested(_ agent: Agent, with event: NSEvent) {
        guard let menu = menuProvider?() else { return }
        press = nil
        NSMenu.popUpContextMenu(menu, with: event, for: agent.view)
    }

    private func clicked(_ agent: Agent, now: TimeInterval) {
        if chat.isOpen(for: agent) {
            chat.close()
            return
        }
        if let exchange { finish(exchange, now: now) }  // no bubbles behind the chat
        hush()
        let companions = agents.filter { $0 !== agent }.map(\.kind)
        let anchor = agent.view.frame.offsetBy(dx: window.frame.minX, dy: window.frame.minY)
        chat.open(agent, anchor: anchor, companions: companions)
        agent.activity = .listening
    }

    private func chatClosed(_ agent: Agent) {
        if agent.activity == .listening {
            agent.setActivity(.idle, for: .random(in: 0.8...2), now: CACurrentMediaTime())
        }
    }
}
