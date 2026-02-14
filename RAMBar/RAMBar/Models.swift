import Foundation

// MARK: - Memory Data Models

struct SystemMemory {
    let total: UInt64      // Total RAM in bytes
    let used: UInt64       // Used RAM in bytes
    let free: UInt64       // Free RAM in bytes
    let wired: UInt64      // Wired (non-swappable) in bytes
    let active: UInt64     // Active pages in bytes
    let inactive: UInt64   // Inactive pages in bytes
    let compressed: UInt64 // Compressed in bytes

    var usedGB: Double { Double(used) / 1_073_741_824 }
    var totalGB: Double { Double(total) / 1_073_741_824 }
    var freeGB: Double { Double(free) / 1_073_741_824 }
    var usagePercent: Double { Double(used) / Double(total) * 100 }

    var status: MemoryStatus {
        let pct = usagePercent
        if pct >= 85 { return .critical }
        if pct >= 70 { return .warning }
        return .nominal
    }
}

enum MemoryStatus {
    case nominal, warning, critical

    var label: String {
        switch self {
        case .nominal: return "NOMINAL"
        case .warning: return "WARNING"
        case .critical: return "CRITICAL"
        }
    }

}

// MARK: - Process Models

struct AppMemory: Identifiable {
    let id = UUID()
    let name: String
    let memory: UInt64  // bytes
    let processCount: Int
    let color: String

    var memoryMB: Double { Double(memory) / 1_048_576 }
    var memoryGB: Double { Double(memory) / 1_073_741_824 }

    var formattedMemory: String {
        if memoryGB >= 1.0 {
            return String(format: "%.1f GB", memoryGB)
        }
        return String(format: "%.0f MB", memoryMB)
    }
}

struct ClaudeSession: Identifiable {
    let id = UUID()
    let pid: Int32
    let projectName: String
    let workingDirectory: String
    let memory: UInt64
    let isSubagent: Bool

    var memoryMB: Double { Double(memory) / 1_048_576 }

    var formattedMemory: String {
        if memoryMB >= 1024 {
            return String(format: "%.1f GB", memoryMB / 1024)
        }
        return String(format: "%.0f MB", memoryMB)
    }
}

struct ChromeTab: Identifiable {
    let id = UUID()
    let title: String
    let url: String
    let memory: UInt64

    var memoryMB: Double { Double(memory) / 1_048_576 }

    var formattedMemory: String {
        String(format: "%.0f MB", memoryMB)
    }
}

struct PythonProcess: Identifiable {
    let id = UUID()
    let pid: Int32
    let script: String
    let memory: UInt64

    var memoryMB: Double { Double(memory) / 1_048_576 }

    var formattedMemory: String {
        if memoryMB >= 1024 {
            return String(format: "%.1f GB", memoryMB / 1024)
        }
        return String(format: "%.0f MB", memoryMB)
    }
}

struct VSCodeWorkspace: Identifiable {
    let id = UUID()
    let name: String
    let memory: UInt64
    let processCount: Int

    var memoryMB: Double { Double(memory) / 1_048_576 }

    var formattedMemory: String {
        if memoryMB >= 1024 {
            return String(format: "%.1f GB", memoryMB / 1024)
        }
        return String(format: "%.0f MB", memoryMB)
    }
}

// MARK: - Diagnostic

struct Diagnostic: Identifiable {
    let id = UUID()
    let message: String
    let severity: DiagnosticSeverity
}

enum DiagnosticSeverity {
    case info, warning, critical
}

// MARK: - App State

struct RAMBarState {
    var systemMemory: SystemMemory?
    var apps: [AppMemory] = []
    var claudeSessions: [ClaudeSession] = []
    var chromeTabs: [ChromeTab] = []
    var pythonProcesses: [PythonProcess] = []
    var vscodeWorkspaces: [VSCodeWorkspace] = []
    var diagnostics: [Diagnostic] = []
    var lastUpdate: Date = Date()
    var memoryHistory: [Double] = []  // Last 30 usage percent readings
}
