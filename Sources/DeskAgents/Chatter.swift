import Foundation

/// Small talk between agents when they bump into each other.
enum Chatter {
    /// Lines alternate: the agent who walked up speaks first.
    private static let generic: [[String]] = [
        ["oh. hi.", "hi. we keep doing this."],
        ["have you seen the cursor?", "it went that way. fast."],
        ["the dock is warm today.", "best spot on the screen."],
        ["do you think they saved their work?", "…no comment."],
        ["i counted the desktop icons.", "how many?", "too many."],
        ["what are you up to?", "walking. mostly walking."],
        ["race you to the edge.", "you go first.", "…i'll go first."],
        ["it's quiet. they must be reading.", "or napping. good for them."],
        ["one more commit?", "it's never one more."],
        ["is it lunch yet?", "we don't eat.", "i know. i just like asking."],
        ["tabs or spaces?", "i'm going to walk away now."],
        ["nice weather on the desktop today.", "it's always the same weather.", "that's what makes it nice."],
    ]

    private static let duets: [[(AgentKind, String)]] = [
        [(.codex, "rm -rf boredom"), (.claude, "please don't run that.")],
        [(.claude, "shipped anything today?"), (.codex, "three commits. one fixed a typo."), (.claude, "honest work.")],
        [(.codex, "i'd write that in one line."), (.claude, "i'd write a comment explaining it.")],
        [(.claude, "want to pair on something?"), (.codex, "you think, i'll type.")],
        [(.claude, "did you run the tests?"), (.codex, "i ran a test."), (.claude, "…a test.")],
        [(.codex, "i fixed the bug."), (.claude, "which one?"), (.codex, "the one i made earlier.")],
        [(.claude, "your face is very expressive today."), (.codex, "> thanks_")],
        [(.codex, "git push --force?"), (.claude, "absolutely not.")],
        [(.codex, "> ls ~/Desktop"), (.claude, "please don't read that out loud.")],
        [(.claude, "what's on your screen?"), (.codex, "a blinking cursor. like me.")],
        [(.claude, "four legs and still slower than you."), (.codex, "i don't have to think as much.")],
    ]

    private static var lastOpener = ""

    static func script(_ first: AgentKind, _ second: AgentKind) -> [(AgentKind, String)] {
        let pair: Set<AgentKind> = [first, second]
        let ours = duets.filter { Set($0.map { $0.0 }) == pair }
        let shared: [[(AgentKind, String)]] = generic.map { lines in
            lines.enumerated().map { ($0.offset % 2 == 0 ? first : second, $0.element) }
        }
        let pool = (ours + ours + shared).filter { $0.first?.1 != lastOpener }
        let pick = pool.randomElement() ?? shared[0]
        lastOpener = pick.first?.1 ?? ""
        return pick
    }

    static func openerPrompt(from me: AgentKind, to other: AgentKind) -> String {
        "You are \(me.name), a tiny line-drawn character wandering along the bottom of someone's Mac desktop. "
            + "You just bumped into \(other.name), another tiny character who lives there too. "
            + "Say one short, playful line to them. Under 12 words, lowercase, no quotes, no emoji. Reply with the line only."
    }

    static func replyPrompt(from me: AgentKind, to other: AgentKind, heard: String) -> String {
        "You are \(me.name), a tiny line-drawn character wandering along the bottom of someone's Mac desktop. "
            + "\(other.name), another tiny character, just bumped into you and said: \"\(heard)\". "
            + "Reply with one short, playful line. Under 12 words, lowercase, no quotes, no emoji. Reply with the line only."
    }

    /// First line only, without wrapping quotes, short enough for a bubble.
    static func tidy(_ raw: String) -> String? {
        let strip = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'“”`*"))
        let line = raw.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: strip) ?? ""
        guard !line.isEmpty else { return nil }
        return line.count > 90 ? String(line.prefix(88)) + "…" : line
    }
}
