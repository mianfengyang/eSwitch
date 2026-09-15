import AppKit

// MARK: - 列表

/// 构建切换列表：所有已打开的常规 GUI 应用。
///
/// v1.4：不按窗口状态、也不按 ⌘H 隐藏状态过滤 —— 无窗应用（进程在、窗口全关）
/// 与隐藏应用都是合法切换目标：激活单纯执行 `open -a <应用真实路径>`（= 点击 Dock 图标），
/// 这条指令既能为无窗应用开出窗口（reopen 事件，实测生效），也能激活任意桌面的应用。
/// 唯一移除条件是进程退出（`isTerminated`；运行中由 AppMonitor 的 didTerminate 通知驱动删卡）。
func getApps() -> [AppInfo] {
    return NSWorkspace.shared.runningApplications.compactMap { app in
        var reason: String? = nil
        // 1) 只列常规 GUI 应用，排除 eSwitch 自身（.accessory）
        if app.activationPolicy != .regular {
            reason = "activationPolicy=\(app.activationPolicy.rawValue)"
        } else if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            reason = "self"
        } else if app.isTerminated {
            // 2) 唯一移除条件：进程退出中（含「没退干净」的僵尸状态）
            reason = "terminated"
        }

        if reason != nil {
            log("getApps: skip \(app.localizedName ?? "pid \(app.processIdentifier)") — \(reason!)")
            return nil
        }
        guard let name = app.localizedName else { return nil }
        // 英文名取自 Info.plist 原始值（不随系统语言本地化）：
        // CFBundleDisplayName → CFBundleName 依次取第一个非空的。
        // 卡片首字母与字母跳转匹配基于英文名；显示名仍是本地化的 name。
        var englishName = name
        if let url = app.bundleURL {
            let plistPath = url.appendingPathComponent("Contents/Info.plist")
            if let dict = NSDictionary(contentsOf: plistPath) as? [String: Any] {
                for key in ["CFBundleDisplayName", "CFBundleName"] {
                    if let v = dict[key] as? String, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        englishName = v
                        break
                    }
                }
            }
        }
        return AppInfo(id: app.bundleIdentifier ?? UUID().uuidString, name: name, englishName: englishName, icon: app.icon, pid: app.processIdentifier)
    }
}

// MARK: - 诊断：切换列表（开发用 --selftest-list）

/// 打印当前呼出将展示的切换列表（与 getApps 同口径）：
/// 每个应用的本地化名/英文名/pid/bundle 路径（即 open -a 实际收到的参数）+ ⌘H 隐藏状态，
/// 用于验证「无窗/隐藏应用也列入、仅进程退出移除」的口径。
func runListSelfTest() {
    let apps = getApps()
    print("== eSwitch 切换列表自检: \(apps.count) apps ==")
    for a in apps {
        let running = NSRunningApplication(processIdentifier: a.pid)
        let hidden = running?.isHidden ?? false
        let path = running?.bundleURL?.path ?? "(无路径)"
        print("  \(a.name)  english=\(a.englishName)  pid=\(a.pid)  hidden=\(hidden ? 1 : 0)  path=\(path)")
    }
    print("")
}
