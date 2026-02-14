import Foundation

// MARK: - Testable pattern matching logic (no AppKit dependency)

/// A pattern entry: name to display, match string, hex color.
/// If pattern starts with "^", it matches only the start of the command (case-insensitive).
/// Otherwise, it matches anywhere in the command (case-insensitive).
public struct AppPattern {
    public let name: String
    public let pattern: String
    public let color: String

    public init(name: String, pattern: String, color: String) {
        self.name = name
        self.pattern = pattern
        self.color = color
    }
}

/// Lightweight process representation for testing
public struct TestProcess {
    public let pid: Int32
    public let command: String
    public let memory: UInt64

    public init(pid: Int32 = 0, command: String, memory: UInt64) {
        self.pid = pid
        self.command = command
        self.memory = memory
    }
}

/// Result of categorizing processes by app
public struct AppCategoryResult {
    public let name: String
    public let memory: UInt64
    public let processCount: Int
    public let color: String
}

/// Check if a command string matches an app pattern.
/// - `^prefix` patterns match case-insensitively at the start of the command
/// - Other patterns match case-insensitively anywhere in the command
public func matchesAppPattern(_ command: String, pattern: String) -> Bool {
    if pattern.hasPrefix("^") {
        let prefix = String(pattern.dropFirst())
        return command.lowercased().hasPrefix(prefix.lowercased())
    } else {
        return command.localizedCaseInsensitiveContains(pattern)
    }
}

/// Default app patterns used by RAMBar
public let defaultAppPatterns: [AppPattern] = [
    AppPattern(name: "Chrome", pattern: "Google Chrome", color: "#4285f4"),
    AppPattern(name: "Claude Code", pattern: "^claude", color: "#cc785c"),
    AppPattern(name: "Cursor", pattern: "Cursor", color: "#00bcd4"),
    AppPattern(name: "VS Code", pattern: "Code Helper", color: "#007acc"),
    AppPattern(name: "Slack", pattern: "Slack", color: "#4a154b"),
    AppPattern(name: "Granola", pattern: "Granola", color: "#f59e0b"),
    AppPattern(name: "Python", pattern: "python", color: "#3776ab"),
    AppPattern(name: "Node.js", pattern: "node", color: "#339933"),
    AppPattern(name: "Docker", pattern: "docker", color: "#2496ed"),
    AppPattern(name: "WhatsApp", pattern: "WhatsApp", color: "#25d366"),
    AppPattern(name: "Obsidian", pattern: "Obsidian", color: "#7c3aed"),
    AppPattern(name: "Safari", pattern: "Safari", color: "#006cff"),
    AppPattern(name: "Arc", pattern: "Arc", color: "#7c3aed"),
    AppPattern(name: "Warp", pattern: "Warp", color: "#01a4ff"),
    AppPattern(name: "Ghostty", pattern: "ghostty", color: "#f97316"),
    AppPattern(name: "iTerm", pattern: "iTerm", color: "#2bbc8a"),
    AppPattern(name: "Figma", pattern: "Figma", color: "#a259ff"),
    AppPattern(name: "Zoom", pattern: "zoom", color: "#2d8cff"),
    AppPattern(name: "Discord", pattern: "Discord", color: "#5865f2"),
    AppPattern(name: "Spotify", pattern: "Spotify", color: "#1db954"),
    AppPattern(name: "Brave", pattern: "Brave", color: "#fb542b"),
    AppPattern(name: "Firefox", pattern: "firefox", color: "#ff7139"),
]

/// Categorize processes into app groups using pattern matching.
/// Returns sorted by memory descending, with an "Other" entry if unmatched > 500MB.
public func categorizeProcesses(_ processes: [TestProcess], patterns: [AppPattern]) -> [AppCategoryResult] {
    var appMemory: [String: (memory: UInt64, count: Int, color: String)] = [:]
    var unmatchedMemory: UInt64 = 0
    var unmatchedCount: Int = 0

    for process in processes {
        var matched = false
        for p in patterns {
            if matchesAppPattern(process.command, pattern: p.pattern) {
                let current = appMemory[p.name] ?? (0, 0, p.color)
                appMemory[p.name] = (current.memory + process.memory, current.count + 1, p.color)
                matched = true
                break
            }
        }
        if !matched {
            unmatchedMemory += process.memory
            unmatchedCount += 1
        }
    }

    var results = appMemory.map { name, data in
        AppCategoryResult(name: name, memory: data.memory, processCount: data.count, color: data.color)
    }.sorted { $0.memory > $1.memory }

    if unmatchedMemory > 500 * 1024 * 1024 {
        results.append(AppCategoryResult(name: "Other", memory: unmatchedMemory, processCount: unmatchedCount, color: "#6b7280"))
    }

    return results
}

/// Filter processes to only actual Claude CLI sessions (not node subprocesses).
/// Only processes whose command starts with "claude" and use > 50MB qualify.
public func filterClaudeSessions(_ processes: [TestProcess]) -> [TestProcess] {
    return processes.filter {
        $0.command.lowercased().hasPrefix("claude") && $0.memory > 50 * 1024 * 1024
    }
}
