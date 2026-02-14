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

    func setPopoverVisible(_ visible: Bool) {
        viewModel.setPopoverVisible(visible)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HeaderView(memory: viewModel.isLoading ? nil : viewModel.state.systemMemory, onRefresh: { viewModel.refreshAsync() }, isRefreshing: viewModel.isRefreshing)

            Rectangle()
                .fill(Color.retroBorder)
                .frame(height: 1)

            if viewModel.isLoading {
                // Loading state
                Spacer()
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.retroCyan)
                    Text("Loading...")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.retroTextDim)
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        // Memory gauge
                        if let memory = viewModel.state.systemMemory {
                            MemoryGaugeView(memory: memory, history: viewModel.state.memoryHistory)
                        }

                        // Apps list with expandable Claude Code and Chrome
                        AppsListView(
                            apps: viewModel.state.apps,
                            claudeSessions: viewModel.state.claudeSessions,
                            chromeTabs: viewModel.state.chromeTabs
                        )

                        // Compact diagnostics
                        if !viewModel.state.diagnostics.isEmpty {
                            DiagnosticsCompactView(diagnostics: viewModel.state.diagnostics)
                        }
                    }
                    .padding()
                }
            }

            Rectangle()
                .fill(Color.retroBorder)
                .frame(height: 1)

            // Footer
            FooterView(lastUpdate: viewModel.state.lastUpdate)
        }
        .frame(width: 380, height: 560)
        .background(Color.retroSurface)
    }
}

// MARK: - View Model

class RAMBarViewModel: ObservableObject {
    @Published var state = RAMBarState()
    @Published var isLoading = true
    @Published var isRefreshing = false

    private var timer: Timer?

    init() {
        // Load full data in background on first open
        refreshAsync()
    }

    deinit {
        timer?.invalidate()
    }

    /// Start/stop the refresh timer based on popover visibility.
    /// No point polling every 3s when the popover is closed — this is the
    /// main fix for the "significant energy" warning.
    func setPopoverVisible(_ visible: Bool) {
        if visible {
            // Refresh immediately when opened, then every 3s
            refreshAsync()
            guard timer == nil else { return }
            let t = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
                self?.refreshAsync()
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    func refreshAsync() {
        guard !isRefreshing else { return }
        isRefreshing = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Get system memory (fast, no shell)
            let memory = MemoryMonitor.shared.getSystemMemory()

            // Get process data — single ps aux call, reused across all queries
            let processes = ProcessMonitor.shared.getProcessList()
            let apps = ProcessMonitor.shared.getAppMemory(from: processes)
            let claude = ProcessMonitor.shared.getClaudeSessions(from: processes)
            let python = ProcessMonitor.shared.getPythonProcesses(from: processes)
            let vscode = ProcessMonitor.shared.getVSCodeWorkspaces(from: processes)
            let chrome = ProcessMonitor.shared.getChromeTabs(from: processes)

            var newState = RAMBarState()
            newState.systemMemory = memory
            newState.apps = apps
            newState.claudeSessions = claude
            newState.pythonProcesses = python
            newState.vscodeWorkspaces = vscode
            newState.chromeTabs = chrome
            newState.lastUpdate = Date()
            newState.diagnostics = ProcessMonitor.shared.generateDiagnostics(state: newState)

            // Track memory history (last 30 readings)
            var history = self?.state.memoryHistory ?? []
            history.append(memory.usagePercent)
            if history.count > 30 { history.removeFirst(history.count - 30) }
            newState.memoryHistory = history

            DispatchQueue.main.async {
                self?.state = newState
                self?.isLoading = false
                self?.isRefreshing = false
            }
        }
    }
}

// MARK: - Header

struct HeaderView: View {
    let memory: SystemMemory?
    var onRefresh: (() -> Void)? = nil
    var isRefreshing: Bool = false

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

            if let memory = memory {
                StatusBadge(status: memory.status)
            }

            if let onRefresh = onRefresh {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.retroTextDim)
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                }
                .buttonStyle(.plain)
                .help("Refresh now")
            }
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
    var history: [Double] = []

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

            // Sparkline showing memory trend
            if history.count >= 2 {
                SparklineView(values: history, color: gaugeColor)
                    .frame(height: 24)
            }

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

// MARK: - Sparkline

struct SparklineView: View {
    let values: [Double]
    let color: Color

    private let warningThreshold: Double = 70
    private let criticalThreshold: Double = 85

    var body: some View {
        GeometryReader { geometry in
            let minVal = (values.min() ?? 0) - 2
            let maxVal = (values.max() ?? 100) + 2
            let range = max(maxVal - minVal, 1)

            // Threshold lines
            ForEach([warningThreshold, criticalThreshold], id: \.self) { threshold in
                if threshold >= minVal && threshold <= maxVal {
                    let y = geometry.size.height * (1 - CGFloat((threshold - minVal) / range))
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                    .stroke(
                        threshold == criticalThreshold ? Color.retroMagenta.opacity(0.3) : Color.retroAmber.opacity(0.3),
                        style: StrokeStyle(lineWidth: 0.5, dash: [4, 3])
                    )
                }
            }

            // Data line
            Path { path in
                for (index, value) in values.enumerated() {
                    let x = geometry.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                    let y = geometry.size.height * (1 - CGFloat((value - minVal) / range))

                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(color, lineWidth: 1.5)

            // Fill below the line
            Path { path in
                for (index, value) in values.enumerated() {
                    let x = geometry.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                    let y = geometry.size.height * (1 - CGFloat((value - minVal) / range))

                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: geometry.size.height))
                        path.addLine(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                path.closeSubpath()
            }
            .fill(color.opacity(0.15))
        }
    }
}

// MARK: - Section Container

struct ExpandableSection<Content: View>: View {
    let title: String
    let icon: String
    let summary: String
    let accentColor: Color
    let content: Content

    @State private var isExpanded = false

    init(
        title: String,
        icon: String,
        summary: String,
        accentColor: Color = .retroCyan,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.summary = summary
        self.accentColor = accentColor
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - clickable
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 10) {
                    // Icon
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isExpanded ? accentColor : .retroTextDim)
                        .frame(width: 16)

                    // Title
                    Text(title)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(isExpanded ? .retroTextPrimary : .retroTextDim)
                        .tracking(1)

                    Spacer()

                    // Summary (when collapsed)
                    if !isExpanded {
                        Text(summary)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.retroTextMuted)
                            .transition(.opacity)
                    }

                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isExpanded ? accentColor : .retroTextMuted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isExpanded ? accentColor.opacity(0.08) : Color.retroSurfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isExpanded ? accentColor.opacity(0.3) : Color.retroBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // Content - animated reveal
            if isExpanded {
                VStack(spacing: 4) {
                    content
                }
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - Apps List

struct AppsListView: View {
    let apps: [AppMemory]
    let claudeSessions: [ClaudeSession]
    let chromeTabs: [ChromeTab]

    // Keep expanded state here so it persists across timer refreshes
    @State private var claudeExpanded = false
    @State private var chromeExpanded = false

    var body: some View {
        VStack(spacing: 4) {
            ForEach(apps) { app in
                if app.name == "Claude Code" && !claudeSessions.isEmpty {
                    ExpandableAppRow(
                        app: app,
                        detailCount: claudeSessions.count,
                        detailLabel: "sessions",
                        isExpanded: $claudeExpanded
                    ) {
                        ClaudeSessionsView(sessions: claudeSessions)
                    }
                } else if app.name == "Chrome" && !chromeTabs.isEmpty {
                    ExpandableAppRow(
                        app: app,
                        detailCount: chromeTabs.count,
                        detailLabel: "tabs",
                        isExpanded: $chromeExpanded
                    ) {
                        ChromeTabsView(tabs: chromeTabs)
                    }
                } else {
                    AppRowView(app: app)
                }
            }
        }
    }
}

struct AppRowView: View {
    let app: AppMemory
    @State private var isHovered = false

    var body: some View {
        let accentColor = Color(hex: app.color) ?? .retroCyan

        Button(action: activateApp) {
            HStack(spacing: 10) {
                // Color accent bar
                Rectangle()
                    .fill(accentColor)
                    .frame(width: 3, height: 32)
                    .cornerRadius(1.5)

                // App name
                Text(app.name)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(.retroTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Process count
                Text("\(app.processCount) proc")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.retroTextMuted)

                // Memory
                Text(app.formattedMemory)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(memoryColor)
                    .frame(width: 70, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isHovered ? accentColor.opacity(0.1) : Color.retroSurfaceRaised)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isHovered ? accentColor.opacity(0.4) : Color.retroBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    var memoryColor: Color {
        if app.memoryGB >= 2 { return .retroMagenta }
        if app.memoryGB >= 1 { return .retroAmber }
        return .retroGreen
    }

    func activateApp() {
        let bundleIds: [String: String] = [
            "Python": "org.python.python",
            "VS Code": "com.microsoft.VSCode",
            "Cursor": "com.todesktop.230313mzl4w4u92",
            "WhatsApp": "net.whatsapp.WhatsApp",
            "Slack": "com.tinyspeck.slackmacgap",
            "Safari": "com.apple.Safari",
            "Node.js": "com.apple.Terminal", // Node usually runs in terminal
            "Finder": "com.apple.finder",
            "Mail": "com.apple.mail",
            "Messages": "com.apple.MobileSMS",
            "Spotify": "com.spotify.client",
            "Discord": "com.hnc.Discord",
            "Zoom": "us.zoom.xos",
            "Firefox": "org.mozilla.firefox",
            "Brave": "com.brave.Browser",
            "Arc": "company.thebrowser.Browser",
            "Notion": "notion.id",
            "Figma": "com.figma.Desktop",
            "Granola": "com.granola.Granola",
            "Docker": "com.docker.docker",
            "Terminal": "com.apple.Terminal",
            "iTerm": "com.googlecode.iterm2",
            "Obsidian": "md.obsidian",
            "Warp": "dev.warp.Warp-Stable",
            "Ghostty": "com.mitchellh.ghostty",
        ]

        if let bundleId = bundleIds[app.name],
           let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            runningApp.activate(options: .activateIgnoringOtherApps)
        } else {
            // Fallback: try to find by app name
            let workspace = NSWorkspace.shared
            if let appURL = workspace.urlForApplication(withBundleIdentifier: app.name.lowercased()) {
                workspace.open(appURL)
            }
        }
    }
}

struct ExpandableAppRow<Content: View>: View {
    let app: AppMemory
    let detailCount: Int
    let detailLabel: String
    @Binding var isExpanded: Bool
    let content: Content

    init(app: AppMemory, detailCount: Int, detailLabel: String, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.app = app
        self.detailCount = detailCount
        self.detailLabel = detailLabel
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        let accentColor = Color(hex: app.color) ?? .retroCyan

        VStack(spacing: 0) {
            // Main row - clickable
            Button(action: {
                isExpanded.toggle()
            }) {
                HStack(spacing: 10) {
                    // Color accent bar
                    Rectangle()
                        .fill(accentColor)
                        .frame(width: 3, height: 32)
                        .cornerRadius(1.5)

                    // App name
                    Text(app.name)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(.retroTextPrimary)

                    // Detail count badge
                    Text("\(detailCount) \(detailLabel)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accentColor.opacity(0.15))
                        .cornerRadius(3)

                    Spacer()

                    // Memory
                    Text(app.formattedMemory)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(memoryColor)

                    // Chevron - animate rotation smoothly
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isExpanded ? accentColor : .retroTextMuted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.15), value: isExpanded)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(isExpanded ? accentColor.opacity(0.08) : Color.retroSurfaceRaised)
                .animation(.easeInOut(duration: 0.15), value: isExpanded)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isExpanded ? accentColor.opacity(0.4) : Color.retroBorder, lineWidth: 1)
                )
                .contentShape(Rectangle()) // Ensure entire row is tappable
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(spacing: 4) {
                    content
                }
                .padding(.top, 6)
                .padding(.leading, 13) // Align with content after accent bar
            }
        }
    }

    var memoryColor: Color {
        if app.memoryGB >= 2 { return .retroMagenta }
        if app.memoryGB >= 1 { return .retroAmber }
        return .retroGreen
    }
}

// MARK: - Claude Sessions

struct ClaudeSessionsView: View {
    let sessions: [ClaudeSession]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(sessions) { session in
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
            ForEach(processes) { process in
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
            ForEach(tabs) { tab in
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

// MARK: - Compact Diagnostics

struct DiagnosticsCompactView: View {
    let diagnostics: [Diagnostic]

    @ViewBuilder
    var body: some View {
        if !diagnostics.isEmpty {
            HStack(spacing: 8) {
                ForEach(diagnostics.prefix(4)) { diagnostic in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(diagnosticColor(diagnostic.severity))
                            .frame(width: 6, height: 6)
                            .shadow(color: diagnosticColor(diagnostic.severity).opacity(0.5), radius: 2)

                        Text(shortMessage(diagnostic.message))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.retroTextMuted)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button(action: openActivityMonitor) {
                    Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                        .font(.caption2)
                        .foregroundColor(.retroTextMuted)
                }
                .buttonStyle(.plain)
                .help("Open Activity Monitor")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.retroSurfaceRaised)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.retroBorder, lineWidth: 1)
            )
            .cornerRadius(6)
        }
    }

    func shortMessage(_ message: String) -> String {
        if message.contains("Nominal") { return "OK" }
        if message.contains("Chrome") { return "Chrome" }
        if message.contains("Memory") { return "RAM" }
        if message.contains("VS Code") { return "VSC" }
        if message.contains("Claude") { return "Claude" }
        return String(message.prefix(8))
    }

    func diagnosticColor(_ severity: DiagnosticSeverity) -> Color {
        switch severity {
        case .info: return .retroGreen
        case .warning: return .retroAmber
        case .critical: return .retroMagenta
        }
    }

    func openActivityMonitor() {
        NSWorkspace.shared.launchApplication("Activity Monitor")
    }
}

// MARK: - Footer

struct FooterView: View {
    let lastUpdate: Date

    var body: some View {
        HStack {
            Text("LAST SYNC: \(lastUpdate, formatter: formatter)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.retroTextMuted)
                .tracking(0.5)

            Spacer()

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

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .medium
        return f
    }()

    var formatter: DateFormatter { Self.timeFormatter }
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
