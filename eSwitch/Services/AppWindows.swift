import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - 「应用是否有真实窗口」统一口径（macOS 27：Accessibility API 为主判据）
//
// 演进记录：
//  - v1.2（macOS 26 时代）：CGWindowList 启发式 —— 菜单栏占位窗不算真实窗口，
//    离屏窗口仅当 CGS 空间归属落在空间环内才算（= 其他桌面的窗口）。
//    问题（macOS 27 实测复现）：用户点关闭按钮后 AppKit 保留的隐藏窗口在 CGS 里
//    常常仍有空间归属（且落在空间环内）→ 被误判为「其他桌面的窗口」→ 无窗应用
//    一直留在切换列表里，要等选中激活一次、自愈标记才把它移出。
//  - macOS 27 实测（26A428 dev beta）：Accessibility 的 kAXWindowsAttribute 对
//    「已关闭全部窗口」的应用（包括 CGS 仍把隐藏窗口归属到空间环的那类）恰好返回
//    0 个窗口，有窗应用计数与实际一致。AX 窗口列表只含用户可交互的真实窗口，
//    是「是否有真实窗口」最可靠的信号。
//  - 依赖辅助功能权限（eSwitch 本就要求；权限被收回或查询失败时自动回退
//    v1.2 的 CGWindowList 启发式，行为与旧版一致，老系统同样安全）。
//  - 待验证项（`--selftest-ax <应用名>`）：macOS 26 曾出现「AX 不返回窗口全在
//    其他桌面的应用的窗口」的问题（v1.2 因此弃用 AX）。若 27 上某应用确有其他
//    桌面的真实窗口而 AX 返回 0，需在本文件 appHasRealWindows() 的 AX 分支里把
//    「离屏且归属空间环的窗口」加回判据（即 hasRealWindow 口径）。

/// 目标应用有多少个真实窗口（Accessibility `kAXWindowsAttribute`）。
/// 辅助功能权限未生效或查询失败时返回 nil（调用方回退 CGWindowList 启发式）。
func axWindowCount(_ pid: pid_t) -> Int? {
    guard AXIsProcessTrusted() else { return nil }
    let element = AXUIElementCreateApplication(pid)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success else {
        return nil
    }
    return (value as? [AXUIElement])?.count ?? 0
}

/// 应用的全部窗口信息（CGWindowListCopyWindowInfo .optionAll，含离屏/隐藏窗口）。
func cgWindowsOf(_ pid: pid_t) -> [[String: Any]] {
    guard let raw = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else { return [] }
    return raw.filter { (($0[kCGWindowOwnerPID as String] as? Int) ?? -1) == Int(pid) }
}

/// CGWindowList 口径：应用是否有**上屏**真实窗口（AX 口径报 0 时的兜底）。
/// 菜单栏占位窗（每个应用都有的 1920x30 一类）上屏但不算真实窗口；
/// layer 2（窗口背景）/ 8（桌面壁纸）一律排除。
func cgHasOnScreenRealWindow(_ windows: [[String: Any]]) -> Bool {
    for info in windows {
        guard (info[kCGWindowIsOnscreen as String] as? Bool) == true else { continue }
        let layer = (info[kCGWindowLayer as String] as? Int) ?? 0
        if layer == 2 || layer == 8 { continue }
        guard let b = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
        let w = b["Width"] ?? 0, h = b["Height"] ?? 0
        guard w > 0, h > 0 else { continue }
        if isMenubarPlaceholder(w: w, h: h) { continue }
        return true
    }
    return false
}

/// 应用是否有真实窗口（**统一口径**：getApps 列表过滤与松键前验活共用）。
///
/// Accessibility 口径可用时以其为主判据：
///   - AX 窗口数 > 0 → 有窗口（AX 窗口列表不含关窗后残留的隐藏窗口）
///   - AX 窗口数 = 0 → CG 上屏口径兜底（窗口正在打开、AX 滞后等瞬态）；无上屏窗 → 无窗口
/// Accessibility 不可用（权限收回等）→ 回退 v1.2 CGWindowList 启发式（见 Apps.swift）。
///
/// - Parameters:
///   - windows: 该应用的窗口信息（getApps 已按 pid 分组时传入，省一次 CGWindowList 枚举）；
///     nil = 未提供 —— AX 分支视为无上屏窗口，回退分支内部自查（枚举失败保守返回 true）。
///   - cgsOK/ringSet: 回退判据所需的 CGS 空间上下文（getApps 已算好时传入，省重复查询）；
///     nil 时内部自查。
func appHasRealWindows(_ pid: pid_t, windows: [[String: Any]]? = nil, cgsOK: Bool? = nil, ringSet: Set<UInt64>? = nil) -> Bool {
    if let axCount = axWindowCount(pid) {
        if axCount > 0 { return true }
        if let windows { return cgHasOnScreenRealWindow(windows) }
        return false
    }
    // Accessibility 不可用（辅助功能权限收回等）→ 回退 v1.2 CGWindowList 启发式
    let ok = cgsOK ?? (cgsSymbol("CGSCopySpacesForWindows") != nil)
    let conn = cgsMainConnectionID()
    let ring = ringSet ?? (ok ? Set(managedDisplaySpaces().flatMap { $0.spaceIDs }) : [])
    if let windows { return hasRealWindow(in: windows, cgsOK: ok, conn: conn, ringSet: ring) }
    return appHasWindows(pid: pid)   // 自查（枚举失败时保守返回 true，保持旧行为）
}

// MARK: - 自检：--selftest-ax <应用名>

/// AX 窗口口径诊断：对比 kAXWindows / kAXVisibleWindows / CGWindowList / 最终判据。
/// 用于验证「窗口在其他桌面时 AX 是否仍返回」这一 macOS 26 遗留疑点，
/// 以及排查「关窗后进程不退出」应用的过滤行为。
func runAXSelfTest(_ query: String) {
    let q = query.lowercased()
    print("== eSwitch AX 窗口口径自检: \(query) ==")
    print("AXIsProcessTrusted = \(AXIsProcessTrusted())")
    let cgsOK = cgsSymbol("CGSCopySpacesForWindows") != nil
    let conn = cgsMainConnectionID()
    let ringSet = cgsOK ? Set(managedDisplaySpaces().flatMap { $0.spaceIDs }) : []
    var matchedAny = false
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
        let name = app.localizedName ?? "?"
        guard q.isEmpty || name.lowercased().contains(q) else { continue }
        matchedAny = true
        let pid = app.processIdentifier
        let ax = AXUIElementCreateApplication(pid)
        var wins: CFTypeRef?
        let eWins = AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &wins)
        var vis: CFTypeRef?
        let eVis = AXUIElementCopyAttributeValue(ax, "AXVisibleWindows" as CFString, &vis)
        let wArr = wins as? [AXUIElement] ?? []
        let vArr = vis as? [AXUIElement] ?? []
        print("\n\(name)  pid=\(pid)  isHidden=\(app.isHidden)  terminated=\(app.isTerminated)")
        print("  AX kAXWindows:        err=\(eWins.rawValue)  n=\(wArr.count)")
        print("  AX kAXVisibleWindows: err=\(eVis.rawValue)  n=\(vArr.count)")
        for (i, win) in wArr.enumerated() {
            var posValue: CFTypeRef?
            AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posValue)
            var sizeValue: CFTypeRef?
            AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeValue)
            var titleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleValue)
            var p = CGPoint.zero
            if let pv = posValue { AXValueGetValue(pv as! AXValue, .cgPoint, &p) }
            var s = CGSize.zero
            if let sv = sizeValue { AXValueGetValue(sv as! AXValue, .cgSize, &s) }
            let title = (titleValue as? String) ?? ""
            print("    win[\(i)] pos=(\(Int(p.x)),\(Int(p.y)))  size=\(Int(s.width))x\(Int(s.height))  title=\"\(title)\"")
        }
        let cg = cgWindowsOf(pid)
        let onCount = cg.filter { ($0[kCGWindowIsOnscreen as String] as? Bool) == true }.count
        let legacy = hasRealWindow(in: cg, cgsOK: cgsOK, conn: conn, ringSet: ringSet)
        print("  CGWindowList: n=\(cg.count)  on-screen=\(onCount)  真实窗口(v1.2启发式)=\(legacy)")
        print("  最终判据 appHasRealWindows = \(appHasRealWindows(pid, windows: cg, cgsOK: cgsOK, ringSet: ringSet))")
    }
    if !matchedAny { print("\n未找到匹配的运行中应用") }
    print("")
}
