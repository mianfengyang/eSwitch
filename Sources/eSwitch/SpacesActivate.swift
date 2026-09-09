import AppKit
import Foundation

// MARK: - Spaces (Virtual Desktops)
/// CoreGraphics 私有 API：切换虚拟桌面 + 查询当前桌面。用于跨桌面激活应用。
/// 符号不存在/调用失败时回退为普通 app.activate，行为不会比改动前差。
typealias CGSSpaceID = UInt32

private func cgsSymbol(_ name: String) -> UnsafeMutableRawPointer? {
    dlsym(dlopen(nil, RTLD_NOW), name)
}

private func cgsMainConnectionID() -> Int32 {
    typealias Fn = @convention(c) () -> Int32
    if let s = cgsSymbol("CGSMainConnectionID") { return unsafeBitCast(s, to: Fn.self)() }
    return 0
}

/// 当前活跃虚拟桌面的 id64（即 CGSSpaceID）
private func cgsCurrentSpaceID() -> CGSSpaceID? {
    typealias Fn = @convention(c) (Int32) -> UInt32
    guard let s = cgsSymbol("CGSGetActiveSpace") else { return nil }
    return unsafeBitCast(s, to: Fn.self)(cgsMainConnectionID())
}

private func cgsSwitchToSpace(_ spaceID: CGSSpaceID) -> Bool {
    typealias Fn = @convention(c) (Int32, CGSSpaceID, Int32, Int32) -> Int32
    guard let s = cgsSymbol("CGSSwitchToSpace") else { return false }
    return unsafeBitCast(s, to: Fn.self)(cgsMainConnectionID(), spaceID, 1, 0) == 0
}

/// 枚举所有虚拟桌面 id64（跨全部显示器的并集，Mission Control 顶部栏顺序）。
/// 数据源：~/Library/Preferences/com.apple.spaces.plist
/// → SpacesDisplayConfiguration → Management Data → Monitors[].Spaces[].id64
/// （macOS 26 实测：旧版 "Space Properties" 键已不存在，CGSGetSpaceID 符号也移除。）
func allSpaceIDs() -> [CGSSpaceID] {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Preferences/com.apple.spaces.plist")
    guard let dict = NSDictionary(contentsOf: url),
          let cfg = dict["SpacesDisplayConfiguration"] as? [String: Any],
          let mgmt = cfg["Management Data"] as? [String: Any],
          let monitors = mgmt["Monitors"] as? [[String: Any]] else { return [] }
    var ids: [CGSSpaceID] = []
    for mon in monitors {
        guard let spaces = mon["Spaces"] as? [[String: Any]] else { continue }
        for s in spaces {
            if let id = s["id64"] as? Int, !ids.contains(CGSSpaceID(id)) {
                ids.append(CGSSpaceID(id))
            }
        }
    }
    return ids
}

/// 应用当前是否有窗口显示在屏幕上（即位于当前桌面）
func appOnScreen(pid: pid_t) -> Bool {
    guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return true }
    return raw.contains { ($0[kCGWindowOwnerPID as String] as? Int) == Int(pid) }
}

/// 扫描所有虚拟桌面，返回该应用有窗口的桌面 id64；找不到返回 nil。
/// 没有任何公开 API 能直接查"窗口属于哪个桌面"，所以做实时探测：
/// 逐个桌面切过去，检查该应用窗口是否 on-screen，命中即停。
/// 只扫非当前桌面；当前桌面由调用方的 onScreen 检查覆盖。
/// 找到目标时系统停在该桌面（调用方直接激活）；找不到则切回原桌面。
func scanSpaceForApp(pid: pid_t) -> CGSSpaceID? {
    let connID = cgsMainConnectionID()
    guard connID != 0, cgsSymbol("CGSSwitchToSpace") != nil else { return nil }
    let current = cgsCurrentSpaceID()
    let candidates = allSpaceIDs().filter { $0 != current }
    guard !candidates.isEmpty else { return nil }

    var found: CGSSpaceID?
    for id in candidates {
        guard cgsSwitchToSpace(id) else { continue }
        Thread.sleep(forTimeInterval: 0.5)  // 等待桌面切换动画结束
        if appOnScreen(pid: pid) {
            found = id
            break
        }
    }
    if found == nil, let c = current {
        // 没找到：恢复原桌面
        let restored = cgsSwitchToSpace(c)
        log("space scan: target not found, restored to space \(c), result=\(restored)")
        Thread.sleep(forTimeInterval: 0.5)
    }
    return found
}

/// 跨虚拟桌面激活应用：当前桌面可见则直接激活；否则扫描所有桌面找到其窗口
/// 所在桌面，停在该桌面后激活。覆盖"所有桌面空间中已打开且有活动窗口的应用"。
/// 扫描涉及多次真实桌面切换（秒级），放到后台线程执行，不阻塞 UI。
func activateApp(_ app: AppInfo) {
    guard let running = NSRunningApplication(processIdentifier: app.pid) else { return }

    // 当前桌面可见 → 直接激活
    if appOnScreen(pid: app.pid) {
        running.activate(options: [.activateIgnoringOtherApps])
        return
    }

    DispatchQueue.global(qos: .userInitiated).async {
        guard let target = scanSpaceForApp(pid: app.pid) else {
            running.activate(options: [.activateIgnoringOtherApps])
            return
        }
        log("activating \(app.name): found on space \(target)")
        // 扫描结束时系统已停在该桌面，稍等动画收尾再激活
        Thread.sleep(forTimeInterval: 0.4)
        running.activate(options: [.activateIgnoringOtherApps])
    }
}
