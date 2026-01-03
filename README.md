# RAMBar

A native macOS menu bar app for monitoring RAM usage with detailed breakdowns for developer workflows.

![RAMBar Screenshot](screenshot.png)

## Features

- **Menu Bar Icon** - Shows current RAM percentage with color-coded status
- **Quick Popover** - Click to see memory breakdown by app
- **Full Dashboard** - Expand to retro-futuristic control room view
- **Developer-Focused Breakdowns**:
  - Claude Code sessions (main vs subagent)
  - VS Code workspaces
  - Chrome tabs by memory
  - Python processes
- **Smart Diagnostics** - Warnings when memory is high or too many sessions active

## Install

### Download
1. Download `RAMBar.dmg` from [Releases](../../releases)
2. Open the DMG and drag RAMBar to Applications
3. Launch RAMBar from Applications
4. **First launch**: Right-click → Open (to bypass Gatekeeper for unsigned app)

### Build from Source
```bash
git clone https://github.com/MaxGhenis/ram-dashboard.git
cd ram-dashboard/RAMBar
xcodebuild -scheme RAMBar -configuration Release build
```

## Usage

- **Click** the menu bar icon to open the popover
- **Click "Full"** in the footer to open the expanded dashboard
- **Click diagnostics** to take action (open Activity Monitor, switch to app)

## Requirements

- macOS 14.0+
- Automation permission for Chrome/VS Code tab enumeration (optional)

## License

MIT
