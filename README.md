# RAMBar

A native macOS menu bar app for monitoring RAM usage, built for developers running Claude Code.

![RAMBar Screenshot](screenshot.png)

## Why I Built This

After Claude 4.5 Opus came out, my Claude Code usage skyrocketed. I was running multiple sessions at once—main agents spawning subagents across different projects—and my 16GB MacBook Air couldn't keep up. VS Code kept crashing. Chrome tabs were piling up. I had no visibility into what was actually consuming memory.

Activity Monitor shows processes, but I needed answers like: *Which Claude session is the memory hog? Can I spawn another subagent? Which Chrome tabs should I close first?*

So I upgraded to a 48GB MacBook Pro, which mostly solved the crashes. But I still wanted to know when I was pushing limits—and RAMBar gives me that visibility.

## Features

- **Menu Bar Icon** - Shows current RAM percentage with color-coded status (green/amber/red)
- **Quick Popover** - Click to see memory breakdown by app
- **Expandable Details**:
  - Claude Code sessions (click to expand, see main vs subagent, memory per session)
  - Chrome tabs (click to expand, see memory per tab)
- **Click-to-Activate** - Click any app row (Python, VS Code, Slack, etc.) to bring it to foreground
- **Smart Diagnostics** - Warnings when memory is high or too many Claude sessions active

## Install

### Homebrew (Recommended)

```bash
brew tap maxghenis/tap
brew install --cask rambar
```

### Download

1. Download `RAMBar.zip` from [Releases](../../releases)
2. Unzip and drag RAMBar to Applications
3. Launch RAMBar from Applications
4. **First launch**: Right-click → Open (to bypass Gatekeeper for unsigned app)

### Build from Source

```bash
git clone https://github.com/MaxGhenis/rambar.git
cd rambar/RAMBar
xcodebuild -scheme RAMBar -configuration Release build
open build/Build/Products/Release/RAMBar.app
```

## Usage

- **Click** the menu bar icon to open the popover
- **Click Claude Code or Chrome rows** to expand and see sessions/tabs
- **Click other app rows** (Python, VS Code, etc.) to bring that app to foreground
- **Click diagnostics** to take action (open Activity Monitor, switch to app)

## Requirements

- macOS 14.0+
- Automation permission for Chrome/VS Code tab enumeration (optional, grants richer details)

## License

MIT
