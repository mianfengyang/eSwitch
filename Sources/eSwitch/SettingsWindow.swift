import AppKit
import SwiftUI

// MARK: - Settings Window
var settingsWindow: NSWindow?

func showSettings() {
    if let existing = settingsWindow, existing.isVisible {
        existing.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        return
    }
    
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 340, height: 395),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    window.title = "eSwitch 设置"
    window.contentView = NSHostingView(rootView: SettingsView())
    window.isReleasedWhenClosed = false
    
    if let screen = NSScreen.main {
        let sf = screen.visibleFrame
        let wf = window.frame
        window.setFrameOrigin(NSPoint(x: sf.midX - wf.width / 2, y: sf.midY - wf.height / 2))
    }
    
    window.makeKeyAndOrderFront(nil)
    NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
    settingsWindow = window
}
