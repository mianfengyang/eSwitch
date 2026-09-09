import AppKit
import ApplicationServices

// MARK: - Apps

/// 应用是否有至少一个可见窗口（AX 查询，辅助功能权限下可用；
/// 无权限时保守返回 true，宁可多列不漏列）
func appHasWindows(pid: pid_t) -> Bool {
    guard AXIsProcessTrusted() else { return true }
    let appElement = AXUIElementCreateApplication(pid)
    var windowsRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
          let windows = windowsRef as? [AXUIElement] else { return true }
    for window in windows {
        var mainRef: CFTypeRef?
        var focusedRef: CFTypeRef?
        // 只认真正可见的窗口：main 或 focused（排除后台隐藏窗口）
        let isMain = AXUIElementCopyAttributeValue(window, kAXMainAttribute as CFString, &mainRef) == .success
            && (mainRef as? Bool ?? false)
        let isFocused = AXUIElementCopyAttributeValue(window, kAXFocusedAttribute as CFString, &focusedRef) == .success
            && (focusedRef as? Bool ?? false)
        if isMain || isFocused { return true }
    }
    // 窗口存在但没有 main/focused 标记的（如被其他全屏应用遮挡时的普通窗口），
    // 仍算可用，避免误杀
    return !windows.isEmpty
}

func getApps() -> [AppInfo] {
    NSWorkspace.shared.runningApplications.filter { app in
        // 1) 只列常规 GUI 应用，排除 eSwitch 自身（.accessory）
        app.activationPolicy == .regular &&
        app.bundleIdentifier != Bundle.main.bundleIdentifier &&
        // 2) 排除正在退出的进程（"没退干净"的僵尸状态）
        !app.isTerminated &&
        // 3) 排除 ⌘H 隐藏的应用
        !app.isHidden &&
        // 4) 兜底：进程活着但没有任何可用窗口的，不列
        appHasWindows(pid: app.processIdentifier)
    }.compactMap { app in
        guard let name = app.localizedName else { return nil }
        return AppInfo(id: app.bundleIdentifier ?? UUID().uuidString, name: name, icon: app.icon, pid: app.processIdentifier)
    }
}
