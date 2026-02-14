import Foundation
import AppKit
import UserNotifications

/// Monitors for app crashes, specifically VSCode
class CrashDetector: ObservableObject {
    static let shared = CrashDetector()

    @Published var vscodeRunning = true
    @Published var lastCrashTime: Date?

    private var vscodeWasRunning = false
    private var observers: [NSObjectProtocol] = []

    private init() {
        setupNotifications()
        requestNotificationPermission()
    }

    deinit {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    private func setupNotifications() {
        let workspace = NSWorkspace.shared.notificationCenter

        // App launched
        let launchObserver = workspace.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppLaunch(notification)
        }
        observers.append(launchObserver)

        // App terminated
        let terminateObserver = workspace.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppTerminate(notification)
        }
        observers.append(terminateObserver)

        // Initial check
        checkVSCodeRunning()
    }

    private func handleAppLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleId = app.bundleIdentifier else { return }

        if bundleId.contains("com.microsoft.VSCode") {
            vscodeRunning = true
            vscodeWasRunning = true
        }
    }

    private func handleAppTerminate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleId = app.bundleIdentifier else { return }

        if bundleId.contains("com.microsoft.VSCode") {
            // Check if it was a crash (unexpected termination)
            if vscodeWasRunning {
                lastCrashTime = Date()
                vscodeRunning = false

                // Send notification
                sendCrashNotification(appName: "VS Code")

                // Log crash
                logCrash(appName: "VS Code", bundleId: bundleId)
            }
            vscodeWasRunning = false
        }
    }

    func checkVSCodeRunning() {
        let runningApps = NSWorkspace.shared.runningApplications
        vscodeRunning = runningApps.contains {
            $0.bundleIdentifier?.contains("com.microsoft.VSCode") == true
        }
        vscodeWasRunning = vscodeRunning
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    private func sendCrashNotification(appName: String) {
        let content = UNMutableNotificationContent()
        content.title = "App Crashed"
        content.body = "\(appName) has stopped unexpectedly"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func sendMemoryWarning(usagePercent: Double) {
        let content = UNMutableNotificationContent()
        content.title = "High Memory Usage"
        content.body = String(format: "System memory at %.0f%% - consider closing apps", usagePercent)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "memory-warning",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Logging

    private func logCrash(appName: String, bundleId: String) {
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".rambar")

        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        let logFile = logDir.appendingPathComponent("crashes.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logEntry = "[\(timestamp)] \(appName) (\(bundleId)) crashed\n"

        if FileManager.default.fileExists(atPath: logFile.path) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(logEntry.data(using: .utf8)!)
                handle.closeFile()
            }
        } else {
            try? logEntry.write(to: logFile, atomically: true, encoding: .utf8)
        }

        // Also capture system state
        captureSystemState(appName: appName)
    }

    private func captureSystemState(appName: String) {
        let memory = MemoryMonitor.shared.getSystemMemory()
        let processes = ProcessMonitor.shared.getProcessList()
        let apps = ProcessMonitor.shared.getAppMemory(from: processes)

        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".rambar")
        let stateFile = logDir.appendingPathComponent("crash-state-\(Int(Date().timeIntervalSince1970)).json")

        var state: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "crashed_app": appName,
            "memory": [
                "total_gb": memory.totalGB,
                "used_gb": memory.usedGB,
                "usage_percent": memory.usagePercent
            ]
        ]

        state["apps"] = apps.prefix(10).map { app in
            ["name": app.name, "memory_mb": app.memoryMB]
        }

        if let data = try? JSONSerialization.data(withJSONObject: state, options: .prettyPrinted) {
            try? data.write(to: stateFile)
        }
    }
}
