# Desk Agents

Pixel versions of the Claude and Codex mascots live along the bottom of your Mac desktop. Claude is the terracotta critter and Codex is the blue cloud-headed bot with a terminal face. They wander, hop, sit and nap. They trade AI-agent-meme banter when they bump into each other, mutter one-liners when alone, and complain when you throw them. Click one to open a small chat with it.

Chats go through each tool's own CLI (`claude -p`, `codex exec`), so they run on your existing logins and subscriptions. No API keys.

## Build and run

```bash
./scripts/bundle.sh
open "build/Desk Agents.app"
```

Needs macOS 14+, Swift 5.10+, and the `claude` and `codex` CLIs installed and logged in.

## Using it

- **Click** an agent to chat with it. Esc, the ×, or clicking elsewhere closes the chat; the conversation is kept until you quit.
- **Hover** over one and it stops and looks at you.
- **Drag** one to pick it up, and let go to drop or throw it.
- **Right-click** an agent (or use the menu-bar walking figure) for the menu:
  - turn agents on or off
  - On the Desktop (behind your windows) or Above All Windows
  - Call Them Over (they walk to your pointer)
  - Real Small Talk: their chatter comes from the real CLIs, at most once every 4 minutes. Uses quota; off by default.
  - Open at Login

The CLIs run in `~/Library/Application Support/DeskAgents/workspace`. Claude runs with no tools and Codex runs in a read-only sandbox.

The sprites are drawn in code (`Sources/DeskAgents/Sprites.swift`): Claude from rectangles, Codex from a pixel grid.

Unofficial fan project, not affiliated with or endorsed by Anthropic or OpenAI. Claude, Codex and their mascots belong to their respective owners.
