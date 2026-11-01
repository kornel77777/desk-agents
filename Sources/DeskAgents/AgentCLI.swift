import Foundation

struct CLIError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Talks to each agent through its own command-line tool, so replies run on
/// the user's existing subscriptions rather than API keys.
enum AgentCLI {
    /// Neutral working folder so the tools don't pick up some random project.
    static let workspace: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("DeskAgents/workspace", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func persona(_ kind: AgentKind, companions: [AgentKind]) -> String {
        let friends = companions.map(\.name).joined(separator: " and ")
        let company = friends.isEmpty ? "" : " alongside \(friends)"
        return """
        You are \(kind.name), drawn as a tiny line-art character who lives on the user's Mac desktop and wanders around\(company). \
        The user just clicked you and opened a small chat bubble. Keep replies short: one to three sentences of plain text, \
        no markdown headings, tables or code blocks unless they ask. Be warm and a little playful, and genuinely helpful when they ask something real.
        """
    }

    static func chatPrompt(_ history: [ChatMessage]) -> String {
        guard let last = history.last else { return "" }
        guard history.count > 1 else { return last.text }
        let earlier = history.dropLast().map { ($0.fromUser ? "User: " : "You: ") + $0.text }
        return "Earlier in this chat:\n" + earlier.joined(separator: "\n") + "\n\nUser's new message: " + last.text
    }

    /// Runs off the main thread; `completion` comes back on the main thread.
    static func ask(_ kind: AgentKind, system: String? = nil, prompt: String, timeout: TimeInterval = 120,
                    completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try run(kind, system: system, prompt: prompt, timeout: timeout) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func run(_ kind: AgentKind, system: String?, prompt: String, timeout: TimeInterval) throws -> String {
        let combined = [system, prompt].compactMap { $0 }.joined(separator: "\n\n")
        switch kind {
        case .claude:
            var args = ["-p", prompt, "--no-session-persistence", "--tools", "", "--strict-mcp-config"]
            if let system { args += ["--append-system-prompt", system] }
            return try exec("claude", args, timeout: timeout)

        case .codex:
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("desk-agents-\(UUID().uuidString).txt")
            defer { try? FileManager.default.removeItem(at: file) }
            _ = try exec("codex", ["exec", "--skip-git-repo-check", "--ephemeral", "-s", "read-only",
                                   "--color", "never", "-o", file.path, combined], timeout: timeout)
            return (try String(contentsOf: file, encoding: .utf8)).trimmingCharacters(in: .whitespacesAndNewlines)

        }
    }

    private static func exec(_ tool: String, _ args: [String], timeout: TimeInterval) throws -> String {
        let process = Process()
        // A login shell finds the tools the same way the user's Terminal does.
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "exec \"$0\" \"$@\"", tool] + args
        process.currentDirectoryURL = workspace

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        env["NO_COLOR"] = "1"
        env.removeValue(forKey: "CLAUDECODE")
        env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
        process.environment = env
        process.standardInput = FileHandle.nullDevice

        let out = Pipe()
        process.standardOutput = out
        let errURL = FileManager.default.temporaryDirectory.appendingPathComponent("desk-agents-\(UUID().uuidString).err")
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        let errHandle = try FileHandle(forWritingTo: errURL)
        defer {
            try? errHandle.close()
            try? FileManager.default.removeItem(at: errURL)
        }
        process.standardError = errHandle

        try process.run()
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        if process.terminationReason == .uncaughtSignal {
            throw CLIError("\(tool) took too long and was stopped.")
        }
        guard process.terminationStatus == 0 else {
            let lines = ((try? String(contentsOf: errURL, encoding: .utf8)) ?? "")
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let detail = lines.last { $0.localizedCaseInsensitiveContains("error") } ?? lines.last
            throw CLIError("\(tool) couldn't answer: \(detail ?? "exit code \(process.terminationStatus)")")
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
