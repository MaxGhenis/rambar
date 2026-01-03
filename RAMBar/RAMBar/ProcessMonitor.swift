import Foundation
import AppKit

/// Monitors running processes and categorizes memory usage
class ProcessMonitor {
    static let shared = ProcessMonitor()

    private init() {}

    // App patterns for categorization
    private let appPatterns: [(name: String, pattern: String, color: String)] = [
        ("Chrome", "Google Chrome", "#4285f4"),
        ("Claude Code", "claude", "#cc785c"),
        ("VS Code", "Code", "#007acc"),
        ("Slack", "Slack", "#4a154b"),
        ("Python", "python", "#3776ab"),
        ("Node.js", "node", "#339933"),
        ("Docker", "docker", "#2496ed"),
        ("WhatsApp", "WhatsApp", "#25d366"),
        ("Obsidian", "Obsidian", "#7c3aed"),
        ("Safari", "Safari", "#006cff"),
    ]

    /// Run a shell command and return output
    private func shell(_ command: String) -> String? {
        let task = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        task.standardOutput = pipe
        task.standardError = errorPipe
        task.standardInput = FileHandle.nullDevice

        // Use /usr/bin/env to find bash - more reliable in app context
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["bash", "-c", command]

        // Set minimal environment - app sandbox may strip custom env vars
        // Note: Use Foundation.ProcessInfo to avoid conflict with local ProcessInfo struct
        var env = Foundation.ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
        env["HOME"] = NSHomeDirectory()
        env["LANG"] = "en_US.UTF-8"
        task.environment = env

        // CRITICAL: Read data BEFORE waitUntilExit to prevent deadlock
        // when output buffer fills up
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

        // Read output in a non-blocking way using dispatch
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

        // Wait for reads to complete (with timeout)
        let result = group.wait(timeout: .now() + 10.0)

        if result == .timedOut {
            task.terminate()
            print("RAMBar shell timeout for '\(command.prefix(50))...'")
            return nil
        }

        task.waitUntilExit()

        let output = String(data: outputData, encoding: .utf8)

        // Log errors for debugging (only if command failed and had stderr output)
        if task.terminationStatus != 0 && !errorData.isEmpty {
            if let errorStr = String(data: errorData, encoding: .utf8), !errorStr.isEmpty {
                print("RAMBar shell stderr for '\(command.prefix(30))...': \(errorStr.prefix(200))")
            }
        }

        return output
    }

    /// Get all running processes with memory info
    func getProcessList() -> [ProcessInfo] {
        var processes: [ProcessInfo] = []

        guard let output = shell("ps aux") else {
            print("Failed to run ps aux")
            return []
        }

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

    /// Get memory usage grouped by app
    func getAppMemory() -> [AppMemory] {
        let processes = getProcessList()
        var appMemory: [String: (memory: UInt64, count: Int, color: String)] = [:]

        for process in processes {
            for (name, pattern, color) in appPatterns {
                if process.command.localizedCaseInsensitiveContains(pattern) {
                    let current = appMemory[name] ?? (0, 0, color)
                    appMemory[name] = (current.memory + process.memory, current.count + 1, color)
                    break
                }
            }
        }

        return appMemory.map { name, data in
            AppMemory(name: name, memory: data.memory, processCount: data.count, color: data.color)
        }.sorted { $0.memory > $1.memory }
    }

    /// Get Claude Code sessions with project info
    func getClaudeSessions() -> [ClaudeSession] {
        let processes = getProcessList().filter {
            $0.command.localizedCaseInsensitiveContains("claude") && $0.memory > 50 * 1024 * 1024
        }

        var sessions: [ClaudeSession] = []

        for process in processes {
            // Try to get working directory
            var workingDir = "Unknown"
            if let lsofOutput = shell("lsof -p \(process.pid) 2>/dev/null | grep cwd | awk '{print $NF}' | head -1") {
                let dir = lsofOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !dir.isEmpty {
                    workingDir = dir
                }
            }

            // Extract project name from path
            let pathComponents = workingDir.split(separator: "/")
            var projectName = "Unknown"
            if let last = pathComponents.last {
                projectName = String(last)
            }

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
    func getChromeTabs() -> [ChromeTab] {
        let processes = getProcessList().filter {
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
        for (index, process) in processes.prefix(15).enumerated() {
            let info = index < tabInfo.count ? tabInfo[index] : (title: "Chrome Tab \(index + 1)", url: "")
            tabs.append(ChromeTab(
                title: String(info.title.prefix(50)),
                url: info.url,
                memory: process.memory
            ))
        }

        return tabs
    }

    /// Get Python processes
    func getPythonProcesses() -> [PythonProcess] {
        let processes = getProcessList().filter {
            $0.command.localizedCaseInsensitiveContains("python") && $0.memory > 10 * 1024 * 1024
        }

        return processes.map { process in
            var script = "Python Process"

            // Try to extract script name
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
    func getVSCodeWorkspaces() -> [VSCodeWorkspace] {
        let processes = getProcessList().filter {
            $0.command.contains("Visual Studio Code") || $0.command.contains("Code Helper")
        }

        guard !processes.isEmpty else { return [] }

        let totalMemory = processes.reduce(0) { $0 + $1.memory }
        let totalCount = processes.count

        // Get window names via AppleScript
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
            // Extract workspace name from window title like "file.swift — ProjectName [SSH: ...]"
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

        // Check memory pressure
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

        // Check Claude sessions
        let mainSessions = state.claudeSessions.filter { !$0.isSubagent }.count
        if mainSessions > 3 {
            diagnostics.append(Diagnostic(
                message: "\(mainSessions) Claude sessions active",
                severity: .warning
            ))
        }

        // Check Chrome memory
        if let chrome = state.apps.first(where: { $0.name == "Chrome" }), chrome.memoryGB > 4 {
            diagnostics.append(Diagnostic(
                message: "Chrome using \(chrome.formattedMemory)",
                severity: .warning
            ))
        }

        // Check VSCode
        if !state.vscodeRunning {
            diagnostics.append(Diagnostic(
                message: "VS Code not running",
                severity: .critical
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
