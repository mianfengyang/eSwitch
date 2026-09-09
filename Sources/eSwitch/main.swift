import AppKit
import ApplicationServices

// MARK: - AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        log("Launched")
        setupStatusBar()
        setupKeyboard()
        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
        }
    }
    
    @objc func showSettingsAction() {
        showSettings()
    }
    
    @objc func checkAccessibility() {
        let hk = SettingsManager.shared.showHotkey
        let alert = NSAlert()
        if AXIsProcessTrusted() {
            alert.messageText = "辅助功能权限已启用"
            alert.informativeText = "使用 \(hk.displayString) 呼出切换器。\n按住 \(hk.modifierString)，每按一次按键切换到下一个应用。\n\(hk.releaseHint)激活当前应用。\n\n可在「设置...」中自定义快捷键。"
            alert.alertStyle = .informational
        } else {
            alert.messageText = "需要辅助功能权限"
            alert.informativeText = "请在系统设置中启用 eSwitch 的辅助功能权限。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "打开系统设置")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            return
        }
        alert.runModal()
    }
    
    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Main
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.delegate = AppDelegate.shared
app.run()
