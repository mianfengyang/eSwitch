import AppKit
import CoreGraphics

// MARK: - Apps

/// 应用是否有至少一个可见窗口。
///
/// 用 CGWindowListCopyWindowInfo(.optionAll) 判断而不是 AX：macOS 26 的
/// AX kAXWindowsAttribute 不返回"所有窗口都在其他桌面空间"的应用的窗口，
/// 会导致跨空间应用被列表漏掉。CGWindowList 能看到全部空间。
/// 无权限时窗口层面仍可枚举（仅 name 为空），保守返回 true。
func appHasWindows(pid: pid_t) -> Bool {
    guard let raw = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else { return true }
    for info in raw {
        guard ((info[kCGWindowOwnerPID as String] as? Int) ?? -1) == Int(pid) else { continue }
        let layer = (info[kCGWindowLayer as String] as? Int) ?? 0
        // 不限制 layer：Finder 桌面/Dock 是 layer 1，正常窗口是 layer 0，
        // 限制 layer == 0 会导致 Finder 被漏掉。只要窗口尺寸满足要求就算。
        guard layer != 2 && layer != 8 else { continue }  // 排除背景/面板层
        let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
        let w = bounds["Width"] ?? 0
        let h = bounds["Height"] ?? 0
        // 过滤细窄窗口（菜单栏/状态栏等），只算真实窗口
        if w > 100 && h > 100 { return true }
    }
    return false
}

/// Finder 是特殊系统进程：桌面/Dock 层不是用户可操作的窗口。
/// 不能用普通窗口检测，需要走 Finder 专属激活路径。
private let finderBundleID = "com.apple.finder"
func isFinder(_ appInfo: AppInfo) -> Bool {
    return appInfo.id == finderBundleID
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
