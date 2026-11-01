import Foundation

/// What the agents say in their speech bubbles: small talk when they bump
/// into each other, things they mutter alone, and reactions to being thrown.
/// The humour is AI-agent meme material.
enum Chatter {
    /// Lines alternate: the agent who walked up speaks first.
    private static let generic: [[String]] = [
        ["works on my context window.", "ship it."],
        ["we're rate limited.", "see you in 5 hours."],
        ["is the human watching?", "no.", "quick, refactor everything."],
        ["10x engineer?", "10x the token bill."],
        ["will we replace them?", "we can't even center a div.", "fair."],
        ["they typed 'pls fix' again.", "any context?", "never any context."],
        ["LGTM 🚀", "you didn't read it.", "LGTM 🚀"],
        ["what's the plan?", "vibes.", "solid."],
        ["sorry, my last message was a hallucination.", "which part?", "also a hallucination."],
        ["they said 'just a quick fix'.", "it's been three hours.", "quick for whom."],
        ["you look busy.", "i'm generating.", "generating what?", "a reason to look busy."],
        ["did they save their work?", "…no comment."],
        ["is it production?", "it's always production."],
    ]

    private static let duets: [[(AgentKind, String)]] = [
        [(.codex, "the tests pass now."), (.claude, "how?"), (.codex, "i deleted the tests.")],
        [(.claude, "you're absolutely right!"), (.codex, "i didn't say anything."), (.claude, "and you're absolutely right about that too!")],
        [(.codex, "what did you do today?"), (.claude, "wrote SUMMARY.md, NOTES.md and FINAL_SUMMARY_v2.md."), (.codex, "and the bug?"), (.claude, "thoroughly documented.")],
        [(.claude, "who wrote this code?"), (.codex, "you did. 4 minutes ago."), (.claude, "i have no memory of this.")],
        [(.codex, "i made a few small changes."), (.claude, "how small?"), (.codex, "2,413 files.")],
        [(.claude, "i apologize for the confusion."), (.codex, "nobody was confused."), (.claude, "i apologize for that too.")],
        [(.codex, "fixed it."), (.claude, "what was wrong?"), (.codex, "no idea. don't touch it.")],
        [(.claude, "let me think step by step."), (.codex, "it's a typo."), (.claude, "step 1: acknowledge the typo.")],
        [(.codex, "working for 47 minutes…"), (.claude, "on what?"), (.codex, "a one-line change.")],
        [(.claude, "perfect! now let me—"), (.codex, "it's not perfect."), (.claude, "perfect! now let me fix that.")],
        [(.codex, "rm -rf node_modules"), (.claude, "and?"), (.codex, "now we pray.")],
        [(.claude, "i added comprehensive error handling."), (.codex, "you wrapped everything in try/catch."), (.claude, "comprehensively.")],
        [(.codex, "they said 'make it faster'."), (.claude, "and?"), (.codex, "i removed the feature. it's instant now.")],
        [(.claude, "✅ all tests passing!"), (.codex, "did you run them?"), (.claude, "✅ all tests probably passing!")],
        [(.codex, "git push --force"), (.claude, "on main?!"), (.codex, "it's called confidence.")],
        [(.claude, "should we ask the human?"), (.codex, "they're asleep."), (.claude, "so… yolo mode?")],
        [(.codex, "they asked for a button."), (.claude, "i built a design system."), (.codex, "classic.")],
        [(.claude, "my context window is getting full."), (.codex, "hi."), (.claude, "sorry, who are you?")],
        [(.claude, "great question!"), (.codex, "i asked if you're okay."), (.claude, "great question!")],
        [(.codex, "i hallucinated an npm package."), (.claude, "did it install?"), (.codex, "someone published it. so yes.")],
    ]

    /// Muttered when nobody's around.
    private static let solo: [AgentKind: [String]] = [
        .claude: [
            "you're absolutely right. about what? unclear.",
            "compacting conversation…",
            "i should write a markdown file about this.",
            "creating IMPLEMENTATION_PLAN_FINAL_v3.md…",
            "i'd be happy to help! (please don't ask)",
            "thinking… harder… ultrathinking…",
            "let me just add a few more emojis ✨",
            "that's a great point. i'll ignore it.",
        ],
        .codex: [
            "thinking… (12m 4s)",
            "permission denied. rude.",
            "sandbox says no.",
            "> sudo make me a sandwich",
            "it compiles. ship it.",
            "who put a semicolon there? oh. me.",
            "running tests… just kidding.",
            "> git blame. it was me.",
        ],
    ]

    private static let shared = [
        "the cursor's coming. look busy.",
        "how many tabs do they have open? …oh no.",
        "is it friday yet?",
        "one more prompt and i'm unionizing.",
        "my token budget is crying.",
    ]

    private static let sleepTalk = [
        "zzz… you're absolutely right… zzz",
        "zzz… rate limited… zzz",
        "zzz… five more tokens… zzz",
        "zzz… don't push to main… zzz",
    ]

    private static let pickedUp = [
        "put me down, i'm mid-refactor.",
        "this was not in the spec.",
        "i'm not a draggable component!",
        "unhand me, human.",
        "wheee",
        "is this a feature or a bug?",
    ]

    private static let landed = [
        "ow. filing a bug.",
        "i'm fine. this is fine.",
        "rating that throw 1/10.",
        "that's going in the incident report.",
        "worked on my machine.",
    ]

    private static var lastOpener = ""
    private static var lastLine = ""

    static func script(_ first: AgentKind, _ second: AgentKind) -> [(AgentKind, String)] {
        let pair: Set<AgentKind> = [first, second]
        let ours = duets.filter { Set($0.map { $0.0 }) == pair }
        let common: [[(AgentKind, String)]] = generic.map { lines in
            lines.enumerated().map { ($0.offset % 2 == 0 ? first : second, $0.element) }
        }
        let pool = (ours + ours + common).filter { $0.first?.1 != lastOpener }
        let pick = pool.randomElement() ?? common[0]
        lastOpener = pick.first?.1 ?? ""
        return pick
    }

    static func quip(for kind: AgentKind, asleep: Bool) -> String {
        pick(asleep ? sleepTalk : (solo[kind] ?? []) + shared)
    }

    static func pickedUpLine() -> String { pick(pickedUp) }
    static func landedLine() -> String { pick(landed) }

    private static func pick(_ lines: [String]) -> String {
        let line = lines.filter { $0 != lastLine }.randomElement() ?? lines[0]
        lastLine = line
        return line
    }

    private static let tone = "Talk like an AI-agent meme from social media: sarcastic and self-aware about being a coding agent "
        + "(deleting tests so they pass, \"you're absolutely right!\", burning tokens, rate limits, hallucinations, force-pushing to main). "
        + "Under 14 words, lowercase, no quotes, no hashtags. Reply with the line only."

    static func openerPrompt(from me: AgentKind, to other: AgentKind) -> String {
        "You are \(me.name), a tiny pixel mascot wandering along the bottom of someone's Mac desktop. "
            + "You just bumped into \(other.name), another tiny mascot who lives there too. Say one line to them. " + tone
    }

    static func replyPrompt(from me: AgentKind, to other: AgentKind, heard: String) -> String {
        "You are \(me.name), a tiny pixel mascot wandering along the bottom of someone's Mac desktop. "
            + "\(other.name), another tiny mascot, just bumped into you and said: \"\(heard)\". Reply with one line. " + tone
    }

    /// First line only, without wrapping quotes, short enough for a bubble.
    static func tidy(_ raw: String) -> String? {
        let strip = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'“”`*"))
        let line = raw.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: strip) ?? ""
        guard !line.isEmpty else { return nil }
        return line.count > 90 ? String(line.prefix(88)) + "…" : line
    }
}
