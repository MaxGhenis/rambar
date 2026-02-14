import Foundation
import AppKit

/// Monitors running processes and categorizes memory usage
class ProcessMonitor {
    static let shared = ProcessMonitor()

    private init() {}

    /// App patterns for categorization — canonical list, also mirrored in RAMBarLib for testing.
    /// Patterns prefixed with "^" match only the start of the command (case-insensitive).
    /// Other patterns match anywhere in the command (case-insensitive).
    static let appPatterns: [(name: String, pattern: String, color: String)] = [
        ("Chrome", "Google Chrome", "#4285f4"),
        ("Claude Code", "^claude", "#cc785c"),
        ("Cursor", "Cursor", "#00bcd4"),
        ("VS Code", "Code Helper", "#007acc"),
        ("Slack", "Slack", "#4a154b"),
        ("Granola", "Granola", "#f59e0b"),
        ("Python", "python", "#3776ab"),
        ("Node.js", "node", "#339933"),
        ("Docker", "docker", "#2496ed"),
        ("WhatsApp", "WhatsApp", "#25d366"),
        ("Obsidian", "Obsidian", "#7c3aed"),
        ("Safari", "Safari", "#006cff"),
        ("Arc", "Arc", "#7c3aed"),
        ("Warp", "Warp", "#01a4ff"),
        ("Ghostty", "ghostty", "#f97316"),
        ("iTerm", "iTerm", "#2bbc8a"),
        ("Figma", "Figma", "#a259ff"),
        ("Zoom", "zoom", "#2d8cff"),
        ("Discord", "Discord", "#5865f2"),
        ("Spotify", "Spotify", "#1db954"),
        ("Brave", "Brave", "#fb542b"),
        ("Firefox", "firefox", "#ff7139"),
    ]

    /// Run a shell command and return output
    private func shell(_ command: String) -> String? {
        let task = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        task.standardOutput = pipe
        task.standardError = errorPipe
        task.standardInput = FileHandle.nullDevice

        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["bash", "-c", command]

        var env = Foundation.ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
        env["HOME"] = NSHomeDirectory()
        env["LANG"] = "en_US.UTF-8"
        task.environment = env

        // Read data BEFORE waitUntilExit to prevent deadlock
        var outputData = Data()
        var errorData = Data()

        let outputHandle = pipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading

        do {
            try task.run()
        } catch {
            print("RAMBar shell launch error for '\(command.prefix(50))...': \(error)")
            return nil
        }

        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global().async {
            outputData = outputHandle.readDataToEndOfFile()
            group.leave()
        }

        group.enter()
        DispatchQueue.global().async {
            errorData = errorHandle.readDataToEndOfFile()
            group.leave()
        }

        let result = group.wait(timeout: .now() + 10.0)

        if result == .timedOut {
            task.terminate()
            print("RAMBar shell timeout for '\(command.prefix(50))...'")
            return nil
        }

        task.waitUntilExit()

        let output = String(data: outputData, encoding: .utf8)

        if task.terminationStatus != 0 && !errorData.isEmpty {
            if let errorStr = String(data: errorData, encoding: .utf8), !errorStr.isEmpty {
                print("RAMBar shell stderr for '\(command.prefix(30))...': \(errorStr.prefix(200))")
            }
        }

        return output
    }

    /// Get all running processes with memory info (single ps aux call)
    func getProcessList() -> [ProcessInfo] {
        guard let output = shell("ps aux") else {
            print("Failed to run ps aux")
            return []
        }

        var processes: [ProcessInfo] = []
        let lines = output.components(separatedBy: "\n").dropFirst() // Skip header

        for line in lines {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 11 else { continue }

            guard let pid = Int32(parts[1]),
                  let rss = UInt64(parts[5]) else { continue }

            let command = parts[10...].joined(separator: " ")
            let memoryBytes = rss * 1024 // RSS is in KB

            if memoryBytes > 1_000_000 { // Only processes > 1MB
                processes.append(ProcessInfo(
                    pid: pid,
                    command: command,
                    memory: memoryBytes
                ))
            }
        }

        return processes
    }

    /// Get memory usage grouped by app.
    /// Uses patterns from RAMBarLib (single source of truth).
    func getAppMemory(from processes: [ProcessInfo]) -> [AppMemory] {
        var appMemory: [String: (memory: UInt64, count: Int, color: String)] = [:]
        var unmatchedMemory: UInt64 = 0
        var unmatchedCount: Int = 0

        for process in processes {
            var matched = false
            for (name, pattern, color) in Self.appPatterns {
                let matches: Bool
                if pattern.hasPrefix("^") {
                    let prefix = String(pattern.dropFirst())
                    matches = process.command.lowercased().hasPrefix(prefix.lowercased())
                } else {
                    matches = process.command.localizedCaseInsensitiveContains(pattern)
                }
                if matches {
                    let current = appMemory[name] ?? (0, 0, color)
                    appMemory[name] = (current.memory + process.memory, current.count + 1, color)
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
            AppMemory(name: name, memory: data.memory, processCount: data.count, color: data.color)
        }.sorted { $0.memory > $1.memory }

        if unmatchedMemory > 500 * 1024 * 1024 {
            results.append(AppMemory(name: "Other", memory: unmatchedMemory, processCount: unmatchedCount, color: "#6b7280"))
        }

        return results
    }

    /// Get Claude Code sessions with project info
    func getClaudeSessions(from processes: [ProcessInfo]) -> [ClaudeSession] {
        let claudeProcesses = processes.filter {
            $0.command.lowercased().hasPrefix("claude") && $0.memory > 50 * 1024 * 1024
        }

        var sessions: [ClaudeSession] = []

        for process in claudeProcesses {
            var workingDir = "Unknown"
            if let lsofOutput = shell("lsof -p \(process.pid) 2>/dev/null | grep cwd | awk '{print $NF}' | head -1") {
                let dir = lsofOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !dir.isEmpty {
                    workingDir = dir
                }
            }

            let pathComponents = workingDir.split(separator: "/")
            let projectName = pathComponents.last.map(String.init) ?? "Unknown"
            let isSubagent = process.memory < 500 * 1024 * 1024

            sessions.append(ClaudeSession(
                pid: process.pid,
                projectName: projectName,
                workingDirectory: workingDir,
                memory: process.memory,
                isSubagent: isSubagent
            ))
        }

        return sessions.sorted { $0.memory > $1.memory }
    }

    /// Get Chrome tabs (approximation based on renderer processes)
    func getChromeTabs(from processes: [ProcessInfo]) -> [ChromeTab] {
        let renderers = processes.filter {
            $0.command.contains("Google Chrome Helper (Renderer)")
        }.sorted { $0.memory > $1.memory }

        // Get actual tab info via AppleScript
        var tabInfo: [(title: String, url: String)] = []

        if let output = shell("""
            osascript -e 'tell application "Google Chrome"
                set tabList to ""
                try
                    repeat with w from 1 to (count of windows)
                        repeat with t from 1 to (count of tabs of window w)
                            set tabTitle to title of tab t of window w
                            set tabURL to URL of tab t of window w
                            set tabList to tabList & tabTitle & "|||" & tabURL & "\\n"
                        end repeat
                    end repeat
                end try
                return tabList
            end tell' 2>/dev/null
            """) {
            let lines = output.components(separatedBy: "\n")
            for line in lines where line.contains("|||") {
                let parts = line.components(separatedBy: "|||")
                if parts.count >= 2 {
                    tabInfo.append((title: parts[0], url: parts[1]))
                }
            }
        }

        // Match tabs with renderer processes (approximate)
        var tabs: [ChromeTab] = []
        for (index, process) in renderers.prefix(15).enumerated() {
            let info = index < tabInfo.count ? tabInfo[index] : (title: "Chrome Tab \(index + 1)", url: "")
            let title = info.title.trimmingCharacters(in: .whitespaces)
            if title.isEmpty || title.lowercased() == "chrome" || title.lowercased() == "new tab" {
                continue
            }
            tabs.append(ChromeTab(
                title: String(title.prefix(50)),
                url: info.url,
                memory: process.memory
            ))
        }

        return tabs
    }

    /// Get Python processes
    func getPythonProcesses(from processes: [ProcessInfo]) -> [PythonProcess] {
        let pythonProcs = processes.filter {
            $0.command.localizedCaseInsensitiveContains("python") && $0.memory > 10 * 1024 * 1024
        }

        return pythonProcs.map { process in
            var script = "Python Process"

            if let match = process.command.range(of: #"([^\s/]+\.py)"#, options: .regularExpression) {
                script = String(process.command[match])
            } else if process.command.contains("voice-mode") {
                script = "voice-mode (MCP)"
            } else if process.command.contains("jupyter") {
                script = "Jupyter"
            } else if process.command.contains("ipython") {
                script = "IPython"
            }

            return PythonProcess(pid: process.pid, script: script, memory: process.memory)
        }.sorted { $0.memory > $1.memory }
    }

    /// Get VS Code workspaces
    func getVSCodeWorkspaces(from processes: [ProcessInfo]) -> [VSCodeWorkspace] {
        let vscodeProcs = processes.filter {
            $0.command.contains("Visual Studio Code") || $0.command.contains("Code Helper")
        }

        guard !vscodeProcs.isEmpty else { return [] }

        let totalMemory = vscodeProcs.reduce(0) { $0 + $1.memory }
        let totalCount = vscodeProcs.count

        var windows: [String] = []

        if let output = shell("""
            osascript -e 'tell application "Visual Studio Code"
                try
                    return name of every window
                end try
            end tell' 2>/dev/null
            """) {
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                windows = trimmed.components(separatedBy: ", ")
            }
        }

        if windows.isEmpty {
            return [VSCodeWorkspace(name: "VS Code (total)", memory: totalMemory, processCount: totalCount)]
        }

        let memPerWindow = totalMemory / UInt64(max(windows.count, 1))
        let procsPerWindow = totalCount / max(windows.count, 1)

        return windows.map { window in
            var name = window
            if let range = window.range(of: " — ") {
                let afterDash = String(window[range.upperBound...])
                name = afterDash.components(separatedBy: " [").first ?? afterDash
            }
            return VSCodeWorkspace(name: name, memory: memPerWindow, processCount: procsPerWindow)
        }
    }

    /// Generate diagnostics based on current state
    func generateDiagnostics(state: RAMBarState) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []

        if let mem = state.systemMemory {
            if mem.usagePercent > 90 {
                diagnostics.append(Diagnostic(
                    message: "Memory critical (\(Int(mem.usagePercent))%)",
                    severity: .critical
                ))
            } else if mem.usagePercent > 80 {
                diagnostics.append(Diagnostic(
                    message: "Memory high (\(Int(mem.usagePercent))%)",
                    severity: .warning
                ))
            }
        }

        let mainSessions = state.claudeSessions.filter { !$0.isSubagent }.count
        if mainSessions > 3 {
            diagnostics.append(Diagnostic(
                message: "\(mainSessions) Claude sessions active",
                severity: .warning
            ))
        }

        if let chrome = state.apps.first(where: { $0.name == "Chrome" }), chrome.memoryGB > 4 {
            diagnostics.append(Diagnostic(
                message: "Chrome using \(chrome.formattedMemory)",
                severity: .warning
            ))
        }

        if diagnostics.isEmpty {
            diagnostics.append(Diagnostic(message: "All systems nominal", severity: .info))
        }

        return diagnostics
    }
}

struct ProcessInfo {
    let pid: Int32
    let command: String
    let memory: UInt64
}
