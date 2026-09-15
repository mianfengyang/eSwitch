// eSwitch — macOS 应用切换器
// Author: Mianfeng Yang (杨绵峰)

import AppKit
import ApplicationServices

// MARK: - AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        log("Launched")
        AppMonitor.shared.start()
        setupStatusBar()
        setupKeyboard()
        // 生命周期 → UI：呼出期间应用启停实时增删卡片（缓存由 AppMonitor 内部维护，这里只管可见状态）
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: nil) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier,
                  let name = app.localizedName else { return }
            let info = AppMonitor.shared.makeInfo(app: app, name: name, englishName: name)
            DispatchQueue.main.async {
                guard isVisible else { return }   // 关闭时 currentApps 下次呼出会全量重建
                addLaunchedApp(info)
            }
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: nil) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = app.bundleIdentifier else { return }
            DispatchQueue.main.async {
                guard isVisible else { return }
                removeTerminatedApp(id: id)
            }
        }
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
            alert.informativeText = "使用 \(hk.displayString) 呼出切换器。\n按住 \(hk.modifierString)，每按一次按键切换到下一个应用。\n\(hk.releaseHint)激活当前应用。\n按住 \(hk.modifierString) 按字母（如 A）可快速定位到该字母应用。\n\n可在「设置...」中自定义快捷键。"
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
if CommandLine.arguments.contains("--selftest-index") {
    runIndexSelfTest()
    exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--selftest-windows"), i + 1 < CommandLine.arguments.count {
    runWindowsSelfTest(CommandLine.arguments[i + 1])
    exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--selftest-ax"), i + 1 < CommandLine.arguments.count {
    runAXSelfTest(CommandLine.arguments[i + 1])
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.delegate = AppDelegate.shared
app.run()
