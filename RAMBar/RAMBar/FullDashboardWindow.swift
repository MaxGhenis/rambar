import SwiftUI
import WebKit

/// Full-screen dashboard window with retro-futuristic web UI
class FullDashboardWindowController: NSObject {
    static let shared = FullDashboardWindowController()

    private var window: NSWindow?
    private var webServer: SimpleWebServer?

    func showWindow() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Start embedded web server
        webServer = SimpleWebServer()
        webServer?.start()

        let contentView = FullDashboardView(serverPort: webServer?.port ?? 3334)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window?.title = "RAM Dashboard"
        window?.contentView = NSHostingView(rootView: contentView)
        window?.center()
        window?.titlebarAppearsTransparent = true
        window?.backgroundColor = NSColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1)
        window?.isReleasedWhenClosed = false
        window?.delegate = self
        window?.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
    }
}

extension FullDashboardWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        webServer?.stop()
        webServer = nil
        window = nil
    }
}

struct FullDashboardView: View {
    let serverPort: Int

    var body: some View {
        WebView(url: URL(string: "http://localhost:\(serverPort)")!)
            .frame(minWidth: 800, minHeight: 600)
    }
}

struct WebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - Embedded Web Server

class SimpleWebServer {
    private var serverSocket: Int32 = -1
    private var isRunning = false
    private var serverThread: Thread?
    var port: Int = 3334

    func start() {
        serverThread = Thread { [weak self] in
            self?.runServer()
        }
        serverThread?.start()

        // Wait for server to start
        Thread.sleep(forTimeInterval: 0.2)
    }

    func stop() {
        isRunning = false
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
    }

    private func runServer() {
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else { return }

        var opt: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY.bigEndian

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult >= 0 else {
            close(serverSocket)
            return
        }

        listen(serverSocket, 5)
        isRunning = true

        while isRunning {
            var clientAddr = sockaddr_in()
            var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)

            let clientSocket = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(serverSocket, $0, &clientLen)
                }
            }

            guard clientSocket >= 0, isRunning else { continue }

            // Handle request in background
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handleRequest(clientSocket)
            }
        }
    }

    private func handleRequest(_ socket: Int32) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(socket, &buffer, buffer.count)

        guard bytesRead > 0 else {
            close(socket)
            return
        }

        let request = String(bytes: buffer.prefix(bytesRead), encoding: .utf8) ?? ""

        let response: String
        let contentType: String

        if request.contains("GET /api/memory") {
            contentType = "application/json"
            response = generateMemoryJSON()
        } else {
            contentType = "text/html"
            response = generateDashboardHTML()
        }

        let httpResponse = """
        HTTP/1.1 200 OK\r
        Content-Type: \(contentType)\r
        Content-Length: \(response.utf8.count)\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        \r
        \(response)
        """

        _ = httpResponse.withCString { ptr in
            write(socket, ptr, strlen(ptr))
        }

        close(socket)
    }

    private func generateMemoryJSON() -> String {
        let memory = MemoryMonitor.shared.getSystemMemory()
        let apps = ProcessMonitor.shared.getAppMemory()
        let claude = ProcessMonitor.shared.getClaudeSessions()
        let python = ProcessMonitor.shared.getPythonProcesses()
        let vscode = ProcessMonitor.shared.getVSCodeWorkspaces()
        let chrome = ProcessMonitor.shared.getChromeTabs()

        var json = "{"
        json += "\"total\":\(Int(memory.totalGB)),"
        json += "\"used\":\(String(format: "%.1f", memory.usedGB)),"
        json += "\"free\":\(String(format: "%.1f", memory.freeGB)),"

        // Apps array
        json += "\"apps\":["
        json += apps.map { app in
            "{\"name\":\"\(app.name)\",\"memory\":\(Int(app.memoryMB)),\"processes\":\(app.processCount),\"color\":\"\(app.color)\"}"
        }.joined(separator: ",")
        json += "],"

        // Claude sessions
        json += "\"claudeSessions\":["
        json += claude.map { s in
            "{\"projectName\":\"\(s.projectName.replacingOccurrences(of: "\"", with: "\\\""))\",\"memory\":\(Int(s.memoryMB)),\"pid\":\(s.pid),\"isSubagent\":\(s.isSubagent)}"
        }.joined(separator: ",")
        json += "],"

        // Python processes
        json += "\"pythonProcesses\":["
        json += python.map { p in
            "{\"script\":\"\(p.script.replacingOccurrences(of: "\"", with: "\\\""))\",\"memory\":\(Int(p.memoryMB)),\"pid\":\(p.pid)}"
        }.joined(separator: ",")
        json += "],"

        // VS Code workspaces
        json += "\"vscodeWorkspaces\":["
        json += vscode.map { v in
            "{\"path\":\"\(v.name.replacingOccurrences(of: "\"", with: "\\\""))\",\"memory\":\(Int(v.memoryMB)),\"processes\":\(v.processCount)}"
        }.joined(separator: ",")
        json += "],"

        // Chrome tabs
        json += "\"chromeTabs\":["
        json += chrome.map { t in
            "{\"title\":\"\(t.title.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: " "))\",\"url\":\"\(t.url.replacingOccurrences(of: "\"", with: "\\\""))\",\"memory\":\(Int(t.memoryMB))}"
        }.joined(separator: ",")
        json += "],"

        json += "\"timestamp\":\"\(ISO8601DateFormatter().string(from: Date()))\""
        json += "}"

        return json
    }

    private func generateDashboardHTML() -> String {
        return dashboardHTML
    }
}

// MARK: - Dashboard HTML

let dashboardHTML = """
<!DOCTYPE html>
<html lang="en">
<head>
  <title>RAM Dashboard</title>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600&family=Chakra+Petch:wght@400;500;600;700&display=swap" rel="stylesheet">
  <style>
    :root {
      --void: #0a0a0f;
      --surface: #12121a;
      --surface-raised: #1a1a24;
      --surface-overlay: #22222e;
      --border: #2a2a3a;
      --border-glow: #3a3a4a;
      --text: #e0e0e8;
      --text-dim: #8888a0;
      --text-muted: #5a5a70;
      --cyan: #00ffd5;
      --cyan-dim: #00c4a7;
      --cyan-glow: rgba(0, 255, 213, 0.15);
      --amber: #ffb800;
      --amber-dim: #cc9400;
      --amber-glow: rgba(255, 184, 0, 0.12);
      --magenta: #ff3d6e;
      --magenta-dim: #cc3158;
      --magenta-glow: rgba(255, 61, 110, 0.12);
      --green: #00ff88;
      --green-dim: #00cc6e;
    }

    * { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      font-family: 'IBM Plex Mono', monospace;
      background: var(--void);
      color: var(--text);
      min-height: 100vh;
      line-height: 1.5;
      position: relative;
    }

    body::before {
      content: '';
      position: fixed;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      background: repeating-linear-gradient(
        0deg,
        transparent,
        transparent 2px,
        rgba(0, 0, 0, 0.15) 2px,
        rgba(0, 0, 0, 0.15) 4px
      );
      pointer-events: none;
      z-index: 1000;
    }

    .container {
      max-width: 1200px;
      margin: 0 auto;
      padding: 1.5rem;
      position: relative;
      z-index: 1;
    }

    .header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 1.5rem;
      padding-bottom: 1rem;
      border-bottom: 1px solid var(--border);
    }

    .header-left {
      display: flex;
      align-items: center;
      gap: 1rem;
    }

    .logo {
      width: 48px;
      height: 48px;
      background: linear-gradient(135deg, var(--surface-raised) 0%, var(--surface) 100%);
      border: 1px solid var(--cyan);
      border-radius: 8px;
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow: 0 0 20px var(--cyan-glow);
    }

    .logo svg {
      width: 26px;
      height: 26px;
      color: var(--cyan);
      filter: drop-shadow(0 0 4px var(--cyan));
    }

    h1 {
      font-family: 'Chakra Petch', sans-serif;
      font-size: 1.5rem;
      font-weight: 700;
      color: var(--text);
      letter-spacing: 0.05em;
      text-transform: uppercase;
    }

    h1 span { color: var(--cyan); text-shadow: 0 0 10px var(--cyan-glow); }

    .status {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      font-size: 0.75rem;
      font-weight: 600;
      padding: 8px 14px;
      border-radius: 4px;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      border: 1px solid;
    }

    .status.ok { background: rgba(0, 255, 136, 0.08); border-color: var(--green); color: var(--green); }
    .status.warning { background: var(--amber-glow); border-color: var(--amber); color: var(--amber); }
    .status.critical { background: var(--magenta-glow); border-color: var(--magenta); color: var(--magenta); animation: pulse 1s infinite; }

    @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.7; } }

    .status-dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      animation: blink 2s ease-in-out infinite;
    }

    .status.ok .status-dot { background: var(--green); box-shadow: 0 0 8px var(--green); }
    .status.warning .status-dot { background: var(--amber); box-shadow: 0 0 8px var(--amber); }
    .status.critical .status-dot { background: var(--magenta); box-shadow: 0 0 8px var(--magenta); }

    @keyframes blink { 0%, 100% { opacity: 1; } 50% { opacity: 0.3; } }

    .gauge-card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 1.5rem;
      margin-bottom: 1.5rem;
    }

    .gauge-header {
      display: flex;
      justify-content: space-between;
      align-items: baseline;
      margin-bottom: 1rem;
    }

    .gauge-label {
      font-family: 'Chakra Petch', sans-serif;
      font-size: 0.875rem;
      color: var(--text-dim);
      text-transform: uppercase;
    }

    .gauge-value {
      font-size: 3rem;
      font-weight: 600;
      color: var(--cyan);
      text-shadow: 0 0 20px var(--cyan-glow);
    }

    .gauge-value span { font-size: 1.25rem; color: var(--text-dim); font-weight: 400; }

    .gauge-bar-container {
      height: 8px;
      background: var(--surface-overlay);
      border-radius: 4px;
      overflow: hidden;
      margin-bottom: 0.5rem;
      border: 1px solid var(--border);
    }

    .stacked-bar { display: flex; height: 100%; border-radius: 3px; overflow: hidden; }
    .stacked-segment { height: 100%; transition: width 0.5s; }

    .gauge-labels { display: flex; justify-content: space-between; font-size: 0.6875rem; color: var(--text-muted); }

    .legend { display: flex; gap: 1rem; margin-top: 1rem; padding-top: 1rem; border-top: 1px solid var(--border); flex-wrap: wrap; font-size: 0.75rem; color: var(--text-dim); }

    .section { margin-bottom: 1.5rem; }
    .section-header { display: flex; align-items: center; gap: 0.75rem; margin-bottom: 0.875rem; }
    .section-number { font-size: 0.625rem; font-weight: 600; color: var(--void); background: var(--cyan); padding: 2px 6px; border-radius: 2px; }
    .section-title { font-family: 'Chakra Petch', sans-serif; font-size: 0.875rem; font-weight: 600; text-transform: uppercase; }

    .apps-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); gap: 0.75rem; }

    .app-card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 6px;
      padding: 0.875rem;
      transition: all 0.2s;
      position: relative;
      overflow: hidden;
    }

    .app-card::before { content: ''; position: absolute; left: 0; top: 0; bottom: 0; width: 3px; }
    .app-card:hover { border-color: var(--border-glow); transform: translateY(-2px); }

    .app-name { font-family: 'Chakra Petch', sans-serif; font-size: 0.75rem; font-weight: 600; text-transform: uppercase; }
    .app-memory { font-size: 1.25rem; font-weight: 600; }
    .app-memory span { font-size: 0.6875rem; color: var(--text-muted); font-weight: 400; }
    .app-processes { font-size: 0.625rem; color: var(--text-muted); margin-top: 0.25rem; }

    .panels-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 0.875rem; margin-bottom: 0.875rem; }
    .panels-grid-2 { display: grid; grid-template-columns: repeat(2, 1fr); gap: 0.875rem; }

    @media (max-width: 900px) { .panels-grid, .panels-grid-2 { grid-template-columns: 1fr; } }

    .panel { background: var(--surface); border: 1px solid var(--border); border-radius: 6px; overflow: hidden; }
    .panel-header { display: flex; align-items: center; gap: 0.5rem; padding: 0.75rem 1rem; border-bottom: 1px solid var(--border); background: var(--surface-raised); }
    .panel-number { font-size: 0.5625rem; font-weight: 600; color: var(--void); background: var(--cyan); padding: 2px 5px; border-radius: 2px; }
    .panel-title { font-family: 'Chakra Petch', sans-serif; font-size: 0.75rem; font-weight: 600; text-transform: uppercase; }
    .panel-meta { font-size: 0.625rem; color: var(--text-muted); margin-left: auto; }
    .panel-content { padding: 0.375rem 0; max-height: 240px; overflow-y: auto; }

    .item { display: flex; justify-content: space-between; align-items: center; padding: 0.5rem 1rem; transition: background 0.15s; border-left: 2px solid transparent; }
    .item:hover { background: var(--surface-raised); border-left-color: var(--cyan); }
    .item-name { font-size: 0.75rem; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; flex: 1; margin-right: 0.75rem; }
    .item-meta { font-size: 0.5625rem; color: var(--text-muted); margin-top: 2px; }
    .item-memory { font-size: 0.75rem; font-weight: 600; white-space: nowrap; }
    .item-memory.high { color: var(--magenta); }
    .item-memory.medium { color: var(--amber); }
    .item-memory.low { color: var(--green); }

    .badge { display: inline-flex; font-size: 0.5rem; font-weight: 600; padding: 2px 5px; border-radius: 2px; text-transform: uppercase; margin-left: 6px; }
    .badge.main { background: var(--amber-glow); color: var(--amber); border: 1px solid var(--amber-dim); }
    .badge.subagent { background: var(--surface-overlay); color: var(--text-muted); border: 1px solid var(--border); }

    .tips-content { padding: 0.875rem 1rem; font-size: 0.75rem; line-height: 1.7; color: var(--text-dim); }
    .tip-item { display: flex; align-items: flex-start; gap: 0.5rem; margin-bottom: 0.5rem; }
    .tip-bullet { width: 4px; height: 4px; background: var(--cyan); border-radius: 1px; margin-top: 0.5rem; box-shadow: 0 0 6px var(--cyan); }

    .footer { text-align: center; padding: 1.25rem 0; margin-top: 1rem; border-top: 1px solid var(--border); }
    .footer-main { font-size: 0.6875rem; color: var(--text-muted); }
    .footer-meta { font-size: 0.625rem; color: var(--text-muted); margin-top: 0.5rem; }
    .footer-meta span { color: var(--cyan); }

    .empty { padding: 1.25rem; text-align: center; color: var(--text-muted); font-size: 0.75rem; font-style: italic; }

    .loading-overlay { position: fixed; inset: 0; background: var(--void); display: flex; flex-direction: column; align-items: center; justify-content: center; z-index: 2000; transition: opacity 0.4s; }
    .loading-overlay.hidden { opacity: 0; visibility: hidden; }
    .loading-spinner { width: 60px; height: 60px; border: 2px solid transparent; border-top-color: var(--cyan); border-right-color: var(--cyan); border-radius: 50%; animation: spin 1s linear infinite; }
    @keyframes spin { to { transform: rotate(360deg); } }
    .loading-text { margin-top: 1.5rem; font-family: 'Chakra Petch', sans-serif; color: var(--cyan); text-transform: uppercase; letter-spacing: 0.15em; }
  </style>
</head>
<body>
  <div class="loading-overlay" id="loading">
    <div class="loading-spinner"></div>
    <div class="loading-text">Scanning System</div>
  </div>
  <div class="container">
    <header class="header">
      <div class="header-left">
        <div class="logo">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <rect x="2" y="2" width="20" height="8" rx="2"></rect>
            <rect x="2" y="14" width="20" height="8" rx="2"></rect>
            <line x1="6" y1="6" x2="6.01" y2="6"></line>
            <line x1="6" y1="18" x2="6.01" y2="18"></line>
          </svg>
        </div>
        <h1><span>RAM</span> Dashboard</h1>
      </div>
      <div class="status ok" id="status"><span class="status-dot"></span><span>NOMINAL</span></div>
    </header>

    <div class="gauge-card">
      <div class="gauge-header">
        <span class="gauge-label">System Memory</span>
        <span class="gauge-value" id="used">--<span> / -- GB</span></span>
      </div>
      <div class="gauge-bar-container"><div class="stacked-bar" id="stacked-bar"></div></div>
      <div class="gauge-labels"><span>0 GB</span><span id="total-label">-- GB</span></div>
      <div class="legend" id="legend"></div>
    </div>

    <section class="section">
      <div class="section-header">
        <span class="section-number">01</span>
        <span class="section-title">Applications</span>
      </div>
      <div class="apps-grid" id="apps"></div>
    </section>

    <div class="panels-grid">
      <div class="panel">
        <div class="panel-header"><span class="panel-number">02</span><span class="panel-title">Claude Code</span><span class="panel-meta" id="cc-total"></span></div>
        <div class="panel-content" id="claude-sessions"></div>
      </div>
      <div class="panel">
        <div class="panel-header"><span class="panel-number">03</span><span class="panel-title">Python</span><span class="panel-meta" id="py-total"></span></div>
        <div class="panel-content" id="python-processes"></div>
      </div>
      <div class="panel">
        <div class="panel-header"><span class="panel-number">04</span><span class="panel-title">VS Code</span><span class="panel-meta" id="vsc-total"></span></div>
        <div class="panel-content" id="vscode-workspaces"></div>
      </div>
    </div>

    <div class="panels-grid-2">
      <div class="panel">
        <div class="panel-header"><span class="panel-number">05</span><span class="panel-title">Chrome Tabs</span><span class="panel-meta" id="chrome-total"></span></div>
        <div class="panel-content" id="chrome-tabs"></div>
      </div>
      <div class="panel">
        <div class="panel-header"><span class="panel-number">06</span><span class="panel-title">Diagnostics</span></div>
        <div class="tips-content" id="tips"></div>
      </div>
    </div>

    <footer class="footer">
      <p class="footer-main">RAM Bar for macOS</p>
      <p class="footer-meta">Auto-refresh 3s · Last sync: <span id="timestamp">--</span></p>
    </footer>
  </div>

  <script>
    let isFirstLoad = true;
    function getMemClass(mb) { return mb >= 500 ? 'high' : mb >= 200 ? 'medium' : 'low'; }
    function formatMem(mb) { return mb >= 1024 ? (mb/1024).toFixed(1) + ' GB' : mb + ' MB'; }
    function hideLoading() { document.getElementById('loading').classList.add('hidden'); }

    async function fetchData() {
      try {
        const res = await fetch('/api/memory');
        const data = await res.json();
        const pct = (data.used / data.total * 100).toFixed(0);

        document.getElementById('used').innerHTML = data.used + '<span> / ' + data.total + ' GB</span>';
        document.getElementById('total-label').textContent = data.total + ' GB';

        const status = document.getElementById('status');
        if (pct > 90) { status.innerHTML = '<span class="status-dot"></span><span>CRITICAL</span>'; status.className = 'status critical'; }
        else if (pct > 75) { status.innerHTML = '<span class="status-dot"></span><span>WARNING</span>'; status.className = 'status warning'; }
        else { status.innerHTML = '<span class="status-dot"></span><span>NOMINAL</span>'; status.className = 'status ok'; }

        document.getElementById('stacked-bar').innerHTML = data.apps.filter(a => a.memory > 100).map(a =>
          '<div class="stacked-segment" style="width:' + (a.memory/data.total/1024*100) + '%;background:' + a.color + '" title="' + a.name + '"></div>'
        ).join('');

        document.getElementById('legend').innerHTML = data.apps.filter(a => a.memory > 100).map(a =>
          '<span style="display:flex;align-items:center;gap:5px;"><span style="width:8px;height:8px;border-radius:2px;background:' + a.color + '"></span>' + a.name + '</span>'
        ).join('');

        document.getElementById('apps').innerHTML = data.apps.filter(a => a.memory > 50).map(a =>
          '<div class="app-card"><style>.app-card::before{background:' + a.color + '}</style>' +
          '<div class="app-name">' + a.name + '</div><div class="app-memory">' + formatMem(a.memory) + '</div>' +
          '<div class="app-processes">' + a.processes + ' proc</div></div>'
        ).join('');

        const ccTotal = data.claudeSessions.reduce((s, c) => s + c.memory, 0);
        const mainSessions = data.claudeSessions.filter(c => c.memory > 200).length;
        document.getElementById('cc-total').textContent = mainSessions + ' main · ' + formatMem(ccTotal);
        document.getElementById('claude-sessions').innerHTML = data.claudeSessions.filter(c => c.memory > 50).map(c =>
          '<div class="item"><div class="item-name">' + c.projectName + '<span class="badge ' + (c.memory > 500 ? 'main' : 'subagent') + '">' + (c.memory > 500 ? 'MAIN' : 'SUB') + '</span><div class="item-meta">PID ' + c.pid + '</div></div><div class="item-memory ' + getMemClass(c.memory) + '">' + formatMem(c.memory) + '</div></div>'
        ).join('') || '<div class="empty">No active sessions</div>';

        const pyTotal = data.pythonProcesses.reduce((s, p) => s + p.memory, 0);
        document.getElementById('py-total').textContent = data.pythonProcesses.length + ' proc · ' + formatMem(pyTotal);
        document.getElementById('python-processes').innerHTML = data.pythonProcesses.map(p =>
          '<div class="item"><div class="item-name">' + p.script + '<div class="item-meta">PID ' + p.pid + '</div></div><div class="item-memory ' + getMemClass(p.memory) + '">' + formatMem(p.memory) + '</div></div>'
        ).join('') || '<div class="empty">No Python processes</div>';

        const vscTotal = data.vscodeWorkspaces.reduce((s, v) => s + v.memory, 0);
        document.getElementById('vsc-total').textContent = data.vscodeWorkspaces.length + ' ws · ' + formatMem(vscTotal);
        document.getElementById('vscode-workspaces').innerHTML = data.vscodeWorkspaces.map(v =>
          '<div class="item"><div class="item-name">' + v.path + '</div><div class="item-memory ' + getMemClass(v.memory) + '">' + formatMem(v.memory) + '</div></div>'
        ).join('') || '<div class="empty">VS Code not running</div>';

        const chromeTotal = data.chromeTabs.reduce((s, t) => s + t.memory, 0);
        document.getElementById('chrome-total').textContent = data.chromeTabs.length + ' tabs · ' + formatMem(chromeTotal);
        document.getElementById('chrome-tabs').innerHTML = data.chromeTabs.slice(0, 15).map(t =>
          '<div class="item"><div class="item-name">' + t.title + '</div><div class="item-memory ' + getMemClass(t.memory) + '">' + t.memory + ' MB</div></div>'
        ).join('');

        const tips = [];
        const chromeApp = data.apps.find(a => a.name === 'Chrome');
        if (chromeApp && chromeApp.memory > 4000) tips.push('Chrome using ' + formatMem(chromeApp.memory) + ' — consider closing tabs');
        if (mainSessions > 3) tips.push(mainSessions + ' Claude Code sessions — consider closing some');
        if (pct > 80) tips.push('Memory pressure high (' + pct + '%) — close unused apps');
        if (tips.length === 0) tips.push('All systems nominal');
        document.getElementById('tips').innerHTML = tips.map(t => '<div class="tip-item"><span class="tip-bullet"></span>' + t + '</div>').join('');

        document.getElementById('timestamp').textContent = new Date(data.timestamp).toLocaleTimeString();

        if (isFirstLoad) { setTimeout(hideLoading, 200); isFirstLoad = false; }
      } catch (e) { console.error(e); }
    }

    fetchData();
    setInterval(fetchData, 3000);
  </script>
</body>
</html>
"""
