import AppKit
import SwiftUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let fromUser: Bool
    let text: String
    var isError = false
}

/// One running conversation per agent; kept while the app runs so closing
/// the bubble doesn't lose it.
final class ChatSession: ObservableObject {
    let kind: AgentKind
    @Published var messages: [ChatMessage] = []
    @Published var draft = ""
    @Published var isWaiting = false

    init(kind: AgentKind) { self.kind = kind }

    func clear() {
        if !isWaiting { messages = [] }
    }
}

final class ChatPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class ChatController: NSObject, NSWindowDelegate {
    static let size = NSSize(width: 320, height: 300)

    var onClose: ((Agent) -> Void)?

    private var panel: ChatPanel?
    private var agent: Agent?
    private var sessions: [AgentKind: ChatSession] = [:]
    private var keyMonitor: Any?

    var isOpen: Bool { panel != nil }
    func isOpen(for agent: Agent) -> Bool { panel != nil && self.agent === agent }

    func open(_ agent: Agent, anchor: NSRect, companions: [AgentKind]) {
        close()
        let session = sessions[agent.kind] ?? ChatSession(kind: agent.kind)
        sessions[agent.kind] = session
        agent.hasUnread = false

        let view = ChatView(
            session: session,
            onSend: { [weak self] in self?.send(session: session, agent: agent, companions: companions) },
            onClose: { [weak self] in self?.close(restoreFocus: true) }
        )
        let panel = ChatPanel(contentRect: NSRect(origin: origin(for: anchor), size: Self.size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: view)
        panel.delegate = self
        self.panel = panel
        self.agent = agent

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, self?.panel?.isKeyWindow == true else { return event }  // Esc
            self?.close(restoreFocus: true)
            return nil
        }
    }

    func close(restoreFocus: Bool = false) {
        guard let panel else { return }
        let agent = self.agent
        self.panel = nil
        self.agent = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel.delegate = nil
        panel.orderOut(nil)
        if restoreFocus { NSApp.deactivate() }
        if let agent { onClose?(agent) }
    }

    /// Clicking anywhere else closes the bubble, like a popover.
    func windowDidResignKey(_ notification: Notification) { close() }

    private func send(session: ChatSession, agent: Agent, companions: [AgentKind]) {
        let text = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !session.isWaiting else { return }
        session.draft = ""
        session.messages.append(ChatMessage(fromUser: true, text: text))
        session.isWaiting = true
        agent.isThinking = true

        let history = Array(session.messages.filter { !$0.isError }.suffix(12))
        AgentCLI.ask(agent.kind, system: AgentCLI.persona(agent.kind, companions: companions),
                     prompt: AgentCLI.chatPrompt(history)) { [weak self] result in
            session.isWaiting = false
            agent.isThinking = false
            switch result {
            case .success(let reply):
                session.messages.append(ChatMessage(fromUser: false, text: reply.isEmpty ? "…" : reply))
            case .failure(let error):
                session.messages.append(ChatMessage(fromUser: false, text: error.localizedDescription, isError: true))
            }
            if self?.isOpen(for: agent) != true { agent.hasUnread = true }
        }
    }

    /// Just above the agent, or below it if there's no room.
    private func origin(for anchor: NSRect) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.screens[0]
        let area = screen.visibleFrame
        let size = Self.size
        var x = anchor.midX - size.width / 2
        var y = anchor.maxY - 2
        if y + size.height > area.maxY - 8 { y = anchor.minY - size.height - 2 }
        x = min(max(x, area.minX + 8), area.maxX - size.width - 8)
        y = min(max(y, area.minY + 8), area.maxY - size.height - 8)
        return NSPoint(x: x, y: y)
    }
}

struct ChatView: View {
    @ObservedObject var session: ChatSession
    let onSend: () -> Void
    let onClose: () -> Void
    @FocusState private var inputFocused: Bool

    private let rule = Color.white.opacity(0.09)

    var body: some View {
        VStack(spacing: 0) {
            header
            rule.frame(height: 1)
            transcript
            rule.frame(height: 1)
            TextField("Message \(session.kind.name)", text: $session.draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($inputFocused)
                .onSubmit(onSend)
                .padding(.horizontal, 14)
                .frame(height: 42)
        }
        .frame(width: ChatController.size.width, height: ChatController.size.height)
        .background(Color(white: 0.055))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .environment(\.colorScheme, .dark)
        .onExitCommand(perform: onClose)
        .onAppear { DispatchQueue.main.async { inputFocused = true } }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(session.kind.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Text(session.kind.command)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.45))
            Spacer()
            if !session.messages.isEmpty && !session.isWaiting {
                Button("clear") { session.clear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.5))
            }
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(white: 0.5))
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if session.messages.isEmpty && !session.isWaiting {
                        Text("Say hi to \(session.kind.name).").foregroundStyle(Color(white: 0.45))
                    }
                    ForEach(session.messages) { MessageRow(message: $0) }
                    if session.isWaiting { ThinkingDots() }
                    Color.clear.frame(height: 1).id("end")
                }
                .font(.system(size: 13))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: session.messages.count) { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: session.isWaiting) { proxy.scrollTo("end", anchor: .bottom) }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
        }
    }
}

private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        if message.fromUser {
            Text(message.text)
                .foregroundStyle(Color(white: 0.6))
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .textSelection(.enabled)
        } else {
            Text(message.text)
                .italic(message.isError)
                .foregroundStyle(message.isError ? Color(white: 0.5) : Color.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}

private struct ThinkingDots: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.35)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 3
            Text(String(repeating: "·", count: step + 1))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(white: 0.5))
        }
    }
}
