import SwiftUI

// MARK: - Retro Theme Colors

extension Color {
    // Background hierarchy
    static let retroVoid = Color(hex: "0a0a0f")!
    static let retroSurface = Color(hex: "12121a")!
    static let retroSurfaceRaised = Color(hex: "1a1a24")!
    static let retroBorder = Color(hex: "2a2a3a")!

    // Text hierarchy
    static let retroTextPrimary = Color(hex: "e0e0e8")!
    static let retroTextDim = Color(hex: "8888a0")!
    static let retroTextMuted = Color(hex: "5a5a70")!

    // Accent colors
    static let retroCyan = Color(hex: "00ffd5")!
    static let retroAmber = Color(hex: "ffb800")!
    static let retroMagenta = Color(hex: "ff3d6e")!
    static let retroGreen = Color(hex: "00ff88")!
}

struct ContentView: View {
    @StateObject private var viewModel = RAMBarViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HeaderView(memory: viewModel.state.systemMemory)

            Rectangle()
                .fill(Color.retroBorder)
                .frame(height: 1)

            ScrollView {
                VStack(spacing: 12) {
                    // Memory gauge
                    if let memory = viewModel.state.systemMemory {
                        MemoryGaugeView(memory: memory)
                    }

                    // Apps section
                    if !viewModel.state.apps.isEmpty {
                        SectionView(title: "APPLICATIONS", number: "01") {
                            AppsGridView(apps: viewModel.state.apps)
                        }
                    }

                    // Claude Sessions
                    if !viewModel.state.claudeSessions.isEmpty {
                        SectionView(title: "CLAUDE CODE", number: "02") {
                            ClaudeSessionsView(sessions: viewModel.state.claudeSessions)
                        }
                    }

                    // Python Processes
                    if !viewModel.state.pythonProcesses.isEmpty {
                        SectionView(title: "PYTHON", number: "03") {
                            PythonProcessesView(processes: viewModel.state.pythonProcesses)
                        }
                    }

                    // VS Code
                    if !viewModel.state.vscodeWorkspaces.isEmpty {
                        SectionView(title: "VS CODE", number: "04") {
                            VSCodeView(workspaces: viewModel.state.vscodeWorkspaces)
                        }
                    }

                    // Chrome Tabs
                    if !viewModel.state.chromeTabs.isEmpty {
                        SectionView(title: "CHROME TABS", number: "05") {
                            ChromeTabsView(tabs: viewModel.state.chromeTabs)
                        }
                    }

                    // Diagnostics
                    DiagnosticsView(diagnostics: viewModel.state.diagnostics)
                }
                .padding()
            }

            Rectangle()
                .fill(Color.retroBorder)
                .frame(height: 1)

            // Footer
            FooterView(lastUpdate: viewModel.state.lastUpdate)
        }
        .frame(width: 380, height: 520)
        .background(Color.retroSurface)
    }
}

// MARK: - View Model

class RAMBarViewModel: ObservableObject {
    @Published var state = RAMBarState()

    private var timer: Timer?
    private var isRefreshing = false

    init() {
        // Initial load with just memory (fast)
        state.systemMemory = MemoryMonitor.shared.getSystemMemory()
        state.lastUpdate = Date()

        // Load full data in background
        refreshAsync()

        // Set up timer with proper run loop mode for menu bar apps
        let t = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshAsync()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    deinit {
        timer?.invalidate()
    }

    func refreshAsync() {
        guard !isRefreshing else { return }
        isRefreshing = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Get system memory (fast, no shell)
            let memory = MemoryMonitor.shared.getSystemMemory()

            // Get process data (uses shell - can be slow)
            let apps = ProcessMonitor.shared.getAppMemory()
            let claude = ProcessMonitor.shared.getClaudeSessions()
            let python = ProcessMonitor.shared.getPythonProcesses()
            let vscode = ProcessMonitor.shared.getVSCodeWorkspaces()
            let chrome = ProcessMonitor.shared.getChromeTabs()

            var newState = RAMBarState()
            newState.systemMemory = memory
            newState.apps = apps
            newState.claudeSessions = claude
            newState.pythonProcesses = python
            newState.vscodeWorkspaces = vscode
            newState.chromeTabs = chrome
            newState.vscodeRunning = CrashDetector.shared.vscodeRunning
            newState.lastUpdate = Date()
            newState.diagnostics = ProcessMonitor.shared.generateDiagnostics(state: newState)

            DispatchQueue.main.async {
                self?.state = newState
                self?.isRefreshing = false
            }
        }
    }
}

// MARK: - Header

struct HeaderView: View {
    let memory: SystemMemory?

    var body: some View {
        HStack {
            Image(systemName: "memorychip")
                .font(.title2)
                .foregroundColor(.retroCyan)
                .shadow(color: .retroCyan.opacity(0.5), radius: 4)

            Text("RAMBar")
                .font(.system(.headline, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(.retroTextPrimary)

            Spacer()
        }
        .padding()
        .background(Color.retroSurfaceRaised)
    }
}

struct StatusBadge: View {
    let status: MemoryStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.6), radius: 4)

            Text(status.label.uppercased())
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(statusColor)
                .tracking(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(statusColor.opacity(0.15))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(statusColor.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(4)
    }

    var statusColor: Color {
        switch status {
        case .nominal: return .retroGreen
        case .warning: return .retroAmber
        case .critical: return .retroMagenta
        }
    }
}

// MARK: - Memory Gauge

struct MemoryGaugeView: View {
    let memory: SystemMemory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SYSTEM MEMORY")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.retroTextDim)
                    .tracking(1.5)

                Spacer()

                Text(String(format: "%.1f / %.0f GB", memory.usedGB, memory.totalGB))
                    .font(.system(.title2, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.retroTextPrimary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.retroVoid)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.retroBorder, lineWidth: 1)
                        )

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [gaugeColor, gaugeColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * CGFloat(memory.usagePercent / 100))
                        .shadow(color: gaugeColor.opacity(0.4), radius: 4)
                }
            }
            .frame(height: 10)

            HStack {
                Text("0 GB")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.retroTextMuted)
                Spacer()
                Text(String(format: "%.0f GB", memory.totalGB))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.retroTextMuted)
            }
        }
        .padding()
        .background(Color.retroSurfaceRaised)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.retroBorder, lineWidth: 1)
        )
        .cornerRadius(8)
    }

    var gaugeColor: Color {
        switch memory.status {
        case .nominal: return .retroGreen
        case .warning: return .retroAmber
        case .critical: return .retroMagenta
        }
    }
}

// MARK: - Section Container

struct SectionView<Content: View>: View {
    let title: String
    let number: String
    let content: Content

    init(title: String, number: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.number = number
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(number)
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.retroVoid)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.retroCyan)
                    .cornerRadius(3)
                    .shadow(color: .retroCyan.opacity(0.4), radius: 3)

                Text(title)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.retroTextDim)
                    .tracking(1.5)
            }

            content
        }
    }
}

// MARK: - Apps Grid

struct AppsGridView: View {
    let apps: [AppMemory]

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(apps.prefix(6)) { app in
                AppCardView(app: app)
            }
        }
    }
}

struct AppCardView: View {
    let app: AppMemory

    var body: some View {
        let accentColor = Color(hex: app.color) ?? .retroCyan

        VStack(alignment: .leading, spacing: 4) {
            Text(app.name)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
                .foregroundColor(.retroTextPrimary)
                .lineLimit(1)

            Text(app.formattedMemory)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(memoryColor)

            Text("\(app.processCount) proc")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.retroTextMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.retroSurfaceRaised)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.retroBorder, lineWidth: 1)
        )
        .overlay(
            Rectangle()
                .fill(accentColor)
                .frame(width: 3)
                .shadow(color: accentColor.opacity(0.5), radius: 3),
            alignment: .leading
        )
    }

    var memoryColor: Color {
        if app.memoryGB >= 2 { return .retroMagenta }
        if app.memoryGB >= 1 { return .retroAmber }
        return .retroCyan
    }
}

// MARK: - Claude Sessions

struct ClaudeSessionsView: View {
    let sessions: [ClaudeSession]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(sessions.prefix(5)) { session in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(session.projectName)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.retroTextPrimary)
                                .lineLimit(1)

                            Text(session.isSubagent ? "SUB" : "MAIN")
                                .font(.system(.caption2, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(session.isSubagent ? .retroTextMuted : .retroAmber)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(session.isSubagent ? Color.retroTextMuted.opacity(0.2) : Color.retroAmber.opacity(0.2))
                                .cornerRadius(2)
                        }

                        Text("PID \(session.pid)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.retroTextMuted)
                    }

                    Spacer()

                    Text(session.formattedMemory)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(session.memoryMB > 500 ? .retroMagenta : session.memoryMB > 200 ? .retroAmber : .retroGreen)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Color.retroSurfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.retroBorder, lineWidth: 1)
                )
                .cornerRadius(4)
            }
        }
    }
}

// MARK: - Python Processes

struct PythonProcessesView: View {
    let processes: [PythonProcess]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(processes.prefix(5)) { process in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(process.script)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.retroTextPrimary)
                            .lineLimit(1)

                        Text("PID \(process.pid)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.retroTextMuted)
                    }

                    Spacer()

                    Text(process.formattedMemory)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(process.memoryMB > 500 ? .retroMagenta : process.memoryMB > 200 ? .retroAmber : .retroGreen)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Color.retroSurfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.retroBorder, lineWidth: 1)
                )
                .cornerRadius(4)
            }
        }
    }
}

// MARK: - VS Code

struct VSCodeView: View {
    let workspaces: [VSCodeWorkspace]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(workspaces.prefix(4)) { workspace in
                HStack {
                    Text(workspace.name)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.retroTextPrimary)
                        .lineLimit(1)

                    Spacer()

                    Text(workspace.formattedMemory)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(workspace.memoryMB > 1000 ? .retroMagenta : workspace.memoryMB > 500 ? .retroAmber : .retroGreen)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Color.retroSurfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.retroBorder, lineWidth: 1)
                )
                .cornerRadius(4)
            }
        }
    }
}

// MARK: - Chrome Tabs

struct ChromeTabsView: View {
    let tabs: [ChromeTab]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(tabs.prefix(5)) { tab in
                HStack {
                    Text(tab.title)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.retroTextPrimary)
                        .lineLimit(1)

                    Spacer()

                    Text(tab.formattedMemory)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(tab.memoryMB > 500 ? .retroMagenta : tab.memoryMB > 200 ? .retroAmber : .retroGreen)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Color.retroSurfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.retroBorder, lineWidth: 1)
                )
                .cornerRadius(4)
            }
        }
    }
}

// MARK: - Diagnostics

struct DiagnosticsView: View {
    let diagnostics: [Diagnostic]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("06")
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.retroVoid)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.retroCyan)
                    .cornerRadius(3)
                    .shadow(color: .retroCyan.opacity(0.4), radius: 3)

                Text("DIAGNOSTICS")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.retroTextDim)
                    .tracking(1.5)

                Spacer()

                Button(action: openActivityMonitor) {
                    Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                        .font(.caption)
                        .foregroundColor(.retroTextMuted)
                }
                .buttonStyle(.plain)
                .help("Open Activity Monitor")
            }

            ForEach(diagnostics) { diagnostic in
                DiagnosticRowView(diagnostic: diagnostic)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.retroSurfaceRaised)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.retroBorder, lineWidth: 1)
        )
        .cornerRadius(8)
    }

    func openActivityMonitor() {
        NSWorkspace.shared.launchApplication("Activity Monitor")
    }
}

struct DiagnosticRowView: View {
    let diagnostic: Diagnostic
    @State private var isHovered = false

    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: 8) {
                Circle()
                    .fill(diagnosticColor(diagnostic.severity))
                    .frame(width: 6, height: 6)
                    .shadow(color: diagnosticColor(diagnostic.severity).opacity(0.5), radius: 3)

                Text(diagnostic.message)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(isHovered ? .retroTextPrimary : .retroTextDim)

                Spacer()

                if isHovered && diagnostic.severity != .info {
                    Image(systemName: actionIcon)
                        .font(.caption2)
                        .foregroundColor(.retroTextMuted)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    var actionIcon: String {
        if diagnostic.message.contains("Chrome") {
            return "arrow.right.circle"
        } else if diagnostic.message.contains("Claude") {
            return "arrow.right.circle"
        } else if diagnostic.message.contains("Memory") {
            return "memorychip"
        } else if diagnostic.message.contains("VS Code") {
            return "arrow.clockwise"
        }
        return "info.circle"
    }

    func handleTap() {
        if diagnostic.message.contains("Chrome") {
            // Activate Chrome
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first {
                app.activate(options: .activateIgnoringOtherApps)
            }
        } else if diagnostic.message.contains("VS Code") {
            // Activate VS Code
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.VSCode").first {
                app.activate(options: .activateIgnoringOtherApps)
            }
        } else if diagnostic.message.contains("Memory") || diagnostic.message.contains("critical") {
            // Open Activity Monitor
            NSWorkspace.shared.launchApplication("Activity Monitor")
        }
    }

    func diagnosticColor(_ severity: DiagnosticSeverity) -> Color {
        switch severity {
        case .info: return .retroGreen
        case .warning: return .retroAmber
        case .critical: return .retroMagenta
        }
    }
}

// MARK: - Footer

struct FooterView: View {
    let lastUpdate: Date

    var body: some View {
        HStack {
            Text("LAST SYNC: \(lastUpdate, formatter: timeFormatter)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.retroTextMuted)
                .tracking(0.5)

            Spacer()

            Button(action: {
                FullDashboardWindowController.shared.showWindow()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption2)
                    Text("FULL")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .tracking(1)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.retroCyan)
            .help("Open full dashboard window")

            Rectangle()
                .fill(Color.retroBorder)
                .frame(width: 1, height: 12)
                .padding(.horizontal, 6)

            Button("QUIT") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(.caption, design: .monospaced))
            .fontWeight(.bold)
            .foregroundColor(.retroTextMuted)
            .tracking(1)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.retroSurfaceRaised)
    }

    var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .medium
        return f
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        self.init(
            red: Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgb & 0x0000FF) / 255.0
        )
    }
}

#Preview {
    ContentView()
}
