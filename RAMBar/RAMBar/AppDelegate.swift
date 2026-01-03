import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var updateTimer: Timer?
    private var lastMemoryWarningTime: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            // Show "Loading..." initially until memory data is available
            button.title = "Loading..."
        }

        // Create popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 520)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: ContentView())

        // Start update timer using scheduledTimer for proper run loop scheduling
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateStatusButton()
            self?.checkMemoryPressure()
        }
        // Also add to common mode so timer fires during UI interactions
        RunLoop.main.add(updateTimer!, forMode: .common)

        // Immediate update - call directly, we're already on main thread
        updateStatusButton()
    }

    func applicationWillTerminate(_ notification: Notification) {
        updateTimer?.invalidate()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            // Ensure popover window is key
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }

        let memory = MemoryMonitor.shared.getSystemMemory()
        let percent = Int(memory.usagePercent)

        // Create attributed string with icon and percentage
        let attachment = NSTextAttachment()
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)

        let symbolName: String
        let color: NSColor

        switch memory.status {
        case .nominal:
            symbolName = "memorychip"
            color = NSColor.systemGreen
        case .warning:
            symbolName = "memorychip.fill"
            color = NSColor.systemOrange
        case .critical:
            symbolName = "memorychip.fill"
            color = NSColor.systemRed
        }

        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            attachment.image = symbol.tinted(with: color)
        }

        let attachmentString = NSAttributedString(attachment: attachment)
        let percentString = NSAttributedString(
            string: " \(percent)%",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: color
            ]
        )

        let combined = NSMutableAttributedString()
        combined.append(attachmentString)
        combined.append(percentString)

        button.attributedTitle = combined
    }

    private func checkMemoryPressure() {
        let memory = MemoryMonitor.shared.getSystemMemory()

        // Send warning if above 85% and not warned in last 5 minutes
        if memory.usagePercent >= 85 {
            let now = Date()
            if lastMemoryWarningTime == nil || now.timeIntervalSince(lastMemoryWarningTime!) > 300 {
                CrashDetector.shared.sendMemoryWarning(usagePercent: memory.usagePercent)
                lastMemoryWarningTime = now
            }
        }
    }
}

// Helper to tint NSImage
extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = self.copy() as! NSImage
        image.lockFocus()
        color.set()
        let imageRect = NSRect(origin: .zero, size: image.size)
        imageRect.fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }
}
