import AppKit
import CoreGraphics

// MARK: - Apps

/// 菜单栏占位窗口形状：每个应用每个显示器各有一个（宽 = 屏宽，高 = 菜单栏高度，
/// 停放在屏幕外或顶部，如 1920x30 / 1728x33）。不能算真实窗口，
/// 否则"关光窗口但进程不退出"的应用永远无法被列表过滤。
private func isMenubarPlaceholder(w: CGFloat, h: CGFloat) -> Bool {
    return h <= 36 && w >= 500
}

/// 判断单个窗口条目是否为"真实窗口"（用户可感知、可被激活带出来的）。
///
/// 规则：
/// 1. 背景/面板层（2/8）不算；
/// 2. 菜单栏占位窗（细窄满屏宽）不算；
/// 3. 上屏窗口算；
/// 4. 离屏窗口：仅当 CGS 查到它归属空间环内的某个 Space 才算（= 在其他桌面的窗口）。
///    AppKit 关窗后保留的隐藏窗口通常查不到空间归属（spaces=[]），不算。
private func isRealWindow(_ info: [String: Any], cgsOK: Bool, conn: Int32, ringSet: Set<UInt64>) -> Bool {
    let layer = (info[kCGWindowLayer as String] as? Int) ?? 0
    guard layer != 2 && layer != 8 else { return false }  // 排除背景/面板层
    let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    let w = bounds["Width"] ?? 0
    let h = bounds["Height"] ?? 0
    guard w > 0 && h > 0 else { return false }
    guard !isMenubarPlaceholder(w: w, h: h) else { return false }  // 菜单栏占位
    if (info[kCGWindowIsOnscreen as String] as? Bool) == true { return true }
    // 离屏：可能是"其他桌面的窗口"（算），也可能是关窗后保留的隐藏窗口（不算）。
    guard cgsOK else { return true }  // 老系统无 CGS 空间符号：退化为旧行为（离屏也算）
    guard let wid = info[kCGWindowNumber as String] as? Int else { return false }
    return spacesOfWindow(CGWindowID(wid), conn: conn).contains(where: { ringSet.contains($0) })
}

/// 给定窗口条目列表里是否至少有一个真实窗口。
func hasRealWindow(in windows: [[String: Any]], cgsOK: Bool, conn: Int32, ringSet: Set<UInt64>) -> Bool {
    return windows.contains { isRealWindow($0, cgsOK: cgsOK, conn: conn, ringSet: ringSet) }
}

/// 应用是否有至少一个真实窗口（便捷入口：自己取窗口列表）。
///
/// 用 CGWindowListCopyWindowInfo(.optionAll) 判断而不是 AX：macOS 26 的
/// AX kAXWindowsAttribute 不返回"所有窗口都在其他桌面空间"的应用的窗口，
/// 会导致跨空间应用被列表漏掉。CGWindowList 能看到全部空间。
/// 无权限时窗口层面仍可枚举（仅 name 为空）；枚举失败时保守返回 true。
func appHasWindows(pid: pid_t) -> Bool {
    guard let raw = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else { return true }
    let cgsOK = cgsSymbol("CGSCopySpacesForWindows") != nil
    let conn = cgsMainConnectionID()
    let ringSet = cgsOK ? Set(managedDisplaySpaces().flatMap { $0.spaceIDs }) : []
    let mine = raw.filter { (($0[kCGWindowOwnerPID as String] as? Int) ?? -1) == Int(pid) }
    return hasRealWindow(in: mine, cgsOK: cgsOK, conn: conn, ringSet: ringSet)
}

// MARK: - "切完无窗"标记（自愈式）
// 有些应用关窗后进程不退出，个别隐藏窗口 CGS 仍会归属到某个 Space，
// 纯窗口判定拦不住这类残留；补一刀激活侧信号：
// 激活后轮询完毕仍无任何上屏窗口 → 打标记，下次建列表时排除。
// 标记只在应用实际出现上屏窗口时解除（开出/还原窗口即恢复列表）；
// 不设时间过期，避免永久无窗应用反复混回列表。pid 复用无影响：
// 新应用若开出窗口会立即解除，若无窗口本就该被排除。
private let suspectQueue = DispatchQueue(label: "eswitch.suspect")
private var suspectPids: Set<pid_t> = []   // suspectQueue 保护

func markSuspectWindowless(_ pid: pid_t) {
    suspectQueue.sync { _ = suspectPids.insert(pid) }
}

/// 应用是否为"切完无窗"且当前仍无上屏窗口（应从列表排除）；出现上屏窗口时解除标记。
func isSuspectWindowless(_ pid: pid_t) -> Bool {
    suspectQueue.sync {
        guard suspectPids.contains(pid) else { return false }
        if appOnScreen(pid: pid) {
            suspectPids.remove(pid)
            return false
        }
        return true
    }
}

// MARK: - 列表

/// Finder 是特殊系统进程：桌面/Dock 层不是用户可操作的窗口。
/// 不能用普通窗口检测，需要走 Finder 专属激活路径。
private let finderBundleID = "com.apple.finder"
func isFinder(_ appInfo: AppInfo) -> Bool {
    return appInfo.id == finderBundleID
}

func getApps() -> [AppInfo] {
    // 窗口列表一次取回、按 pid 分组（optionAll：含所有 Space / 离屏 / 最小化）
    let raw = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]]
    var windowsByPid: [Int: [[String: Any]]] = [:]
    for info in raw ?? [] {
        let pid = (info[kCGWindowOwnerPID as String] as? Int) ?? -1
        if pid >= 0 { windowsByPid[pid, default: []].append(info) }
    }
    let cgsOK = cgsSymbol("CGSCopySpacesForWindows") != nil
    let conn = cgsMainConnectionID()
    let ringSet = cgsOK ? Set(managedDisplaySpaces().flatMap { $0.spaceIDs }) : []

    return NSWorkspace.shared.runningApplications.compactMap { app in
        let pid = app.processIdentifier
        var reason: String? = nil
        // 1) 只列常规 GUI 应用，排除 eSwitch 自身（.accessory）
        if app.activationPolicy != .regular {
            reason = "activationPolicy=\(app.activationPolicy.rawValue)"
        } else if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            reason = "self"
        } else if app.isTerminated {
            // 2) 排除正在退出的进程（"没退干净"的僵尸状态）
            reason = "terminated"
        } else if app.isHidden {
            // 3) 排除 ⌘H 隐藏的应用
            reason = "hidden"
        } else if raw != nil, !hasRealWindow(in: windowsByPid[Int(pid)] ?? [], cgsOK: cgsOK, conn: conn, ringSet: ringSet) {
            // 4) 兜底：进程活着但没有真实窗口（菜单栏占位/隐藏窗口不算），不列。
            //    窗口枚举失败（raw == nil）时保守列入，保持旧行为。
            reason = "no real window"
        } else if isSuspectWindowless(pid) {
            // 5) 最近激活过且切完无窗（自愈标记，开出窗口即恢复）
            reason = "windowless after activate"
        }

        if reason != nil {
            log("getApps: skip \(app.localizedName ?? "pid \(app.processIdentifier)") — \(reason!)")
            return nil
        }
        guard let name = app.localizedName else { return nil }
        return AppInfo(id: app.bundleIdentifier ?? UUID().uuidString, name: name, icon: app.icon, pid: app.processIdentifier)
    }
}

// MARK: - 诊断：应用窗口列表详情（开发用 --selftest-windows）

/// 打印指定应用在全窗口列表（.optionAll，含所有 Space/离屏/最小化）里的全部窗口条目：
/// 尺寸/alpha/layer/上屏状态 + CGS 空间归属 + 是否判定为真实窗口。
/// 用于校准 appHasWindows 的过滤条件。
func runWindowsSelfTest(_ query: String) {
    let q = query.lowercased()
    let matches = NSWorkspace.shared.runningApplications
        .filter { ($0.bundleIdentifier?.lowercased() == q) || ($0.localizedName?.lowercased() == q) }
    guard let app = matches.first else {
        print("no running app matching '\(query)'")
        return
    }
    let pid = app.processIdentifier
    print("app: \(app.localizedName ?? "?")  bundle=\(app.bundleIdentifier ?? "?")  pid=\(pid)  policy=\(app.activationPolicy.rawValue)  hidden=\(app.isHidden)  terminated=\(app.isTerminated)")
    guard let raw = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
        print("  (窗口枚举失败)")
        return
    }
    let cgsOK = cgsSymbol("CGSCopySpacesForWindows") != nil
    let conn = cgsMainConnectionID()
    let ringSet = cgsOK ? Set(managedDisplaySpaces().flatMap { $0.spaceIDs }) : []
    var count = 0
    for info in raw where ((info[kCGWindowOwnerPID as String] as? Int) ?? -1) == Int(pid) {
        count += 1
        let layer = (info[kCGWindowLayer as String] as? Int) ?? -999
        let alpha = (info[kCGWindowAlpha as String] as? Double) ?? -1
        let onScreen = (info[kCGWindowIsOnscreen as String] as? Bool) ?? false
        let b = info[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
        let w = b["Width"] ?? -1
        let h = b["Height"] ?? -1
        let x = b["X"] ?? 0
        let y = b["Y"] ?? 0
        let name = (info[kCGWindowName as String] as? String) ?? ""
        let alphaStr = alpha < 0 ? "?" : String(format: "%.2f", alpha)
        print("  #\(count)  layer=\(layer)  alpha=\(alphaStr)  onScreen=\(onScreen ? 1 : 0)  \(Int(w))x\(Int(h)) @ (\(Int(x)),\(Int(y)))  name=\(name.prefix(32))")
        if let wid = info[kCGWindowNumber as String] as? Int {
            let spaces = spacesOfWindow(CGWindowID(wid), conn: conn)
            let inRing = spaces.filter { ringSet.contains($0) }
            let real = isRealWindow(info, cgsOK: cgsOK, conn: conn, ringSet: ringSet)
            print("        wid=\(wid)  spaces=\(spaces)  归属空间环: \(inRing.isEmpty ? "否" : "是 \(inRing)")  判定真实窗口: \(real ? "是" : "否")")
        }
    }
    if count == 0 { print("  (全窗口列表中无任何窗口)") }
    print("  total: \(count) windows, appHasWindows=\(appHasWindows(pid: pid))  isSuspectWindowless=\(isSuspectWindowless(pid))")
}
