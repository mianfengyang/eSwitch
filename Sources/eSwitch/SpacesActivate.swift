import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Spaces (Virtual Desktops)
// macOS 26 上 CGS 直接切换空间的私有符号（CGSSwitchToSpace 等）已被移除。
// 实测合成 ⌃+数字（CGEvent keyboard events）可以触发系统"切换桌面"快捷键，
// 因此采用更可靠的方案：按桌面序号绝对定位跳转。
// 窗口→空间没有公开/可靠 API，所以采用探测扫描：
//   对该显示器每个桌面序号依次 ⌃+N 跳转，每步检查该 PID 是否有窗口上屏，命中即停。
// 每次跳转是绝对定位（指定序号），不依赖连续滑动，不会累积误差。
// 需要辅助功能权限（AXIsProcessTrusted），eSwitch 启动时已请求。
typealias CGSSpaceID = UInt32

private func cgsSymbol(_ name: String) -> UnsafeMutableRawPointer? {
    dlsym(dlopen(nil, RTLD_NOW), name)
}

private func cgsMainConnectionID() -> Int32 {
    typealias Fn = @convention(c) () -> Int32
    if let s = cgsSymbol("CGSMainConnectionID") { return unsafeBitCast(s, to: Fn.self)() }
    return 0
}

struct ManagedDisplay {
    /// 显示器标识（CGSCopyManagedDisplaySpaces 的 "Display Identifier"，
    /// 与 CGDisplayCreateUUIDFromDisplayID 的字符串一致）
    let identifier: String
    /// 该显示器当前空间 id64
    var currentSpaceID: UInt64?
    /// 有序空间 id64 列表（Mission Control 顶部栏顺序，环状）
    let spaceIDs: [UInt64]
}

/// 读取全部显示器的空间环。数据源为 CGS 私有 API CGSCopyManagedDisplaySpaces
/// （替代已过时的 plist 路径），macOS 26 实测可用。
func managedDisplaySpaces() -> [ManagedDisplay] {
    typealias Fn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    guard let s = cgsSymbol("CGSCopyManagedDisplaySpaces") else { return [] }
    let conn = cgsMainConnectionID()
    guard let arr = unsafeBitCast(s, to: Fn.self)(conn)?.takeRetainedValue() as? [[String: Any]] else { return [] }

    var result: [ManagedDisplay] = []
    for display in arr {
        guard let ident = display["Display Identifier"] as? String else { continue }
        let current = (display["Current Space"] as? [String: Any])?["id64"] as? NSNumber
        let spaces = (display["Spaces"] as? [[String: Any]] ?? [])
            .compactMap { ($0["id64"] as? NSNumber)?.uint64Value }
        result.append(ManagedDisplay(identifier: ident, currentSpaceID: current?.uint64Value, spaceIDs: spaces))
    }
    return result
}

/// 某一显示器的当前空间 id64（走 CGS 私有符号，不需要辅助功能权限）
func cgsDisplayCurrentSpace(identifier: String) -> UInt64? {
    typealias Fn = @convention(c) (Int32, CFString) -> UInt64
    guard let s = cgsSymbol("CGSManagedDisplayGetCurrentSpace") else { return nil }
    return unsafeBitCast(s, to: Fn.self)(cgsMainConnectionID(), identifier as CFString)
}

/// 应用当前是否有窗口显示在屏幕上（即位于当前空间）
func appOnScreen(pid: pid_t) -> Bool {
    guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return true }
    return raw.contains { ($0[kCGWindowOwnerPID as String] as? Int) == Int(pid) }
}

/// 把光标移到指定显示器中心（手势落点跟随光标所在显示器）。
func warpCursorToDisplay(_ displayID: CGDirectDisplayID) {
    let bounds = CGDisplayBounds(displayID)
    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    _ = CGWarpMouseCursorPosition(center)
}

struct ManagedDisplayID {
    let displayID: CGDirectDisplayID
    let uuid: String
}

/// 枚举在线显示器及其 UUID（与 CGSCopyManagedDisplaySpaces 的 identifier 对应）
func onlineDisplays() -> [ManagedDisplayID] {
    let maxCount: UInt32 = 32
    var count: UInt32 = 0
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(maxCount))
    CGGetOnlineDisplayList(maxCount, &ids, &count)
    var result: [ManagedDisplayID] = []
    for i in 0..<Int(count) {
        let id = ids[i]
        guard let uuidRef = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { continue }
        let str = CFUUIDCreateString(nil, uuidRef) as String
        result.append(ManagedDisplayID(displayID: id, uuid: str))
    }
    return result
}

// 数字键 → keycode（物理键盘布局）
let digitKeycodes: [Int: CGKeyCode] = [1:18, 2:19, 3:20, 4:21, 5:23, 6:22, 7:26, 8:28, 9:25, 0:29]

/// 合成 ⌃+数字 n 的按键事件（实测 macOS 26 上可切换桌面）。
func postCtrlDigit(_ n: Int) {
    guard let key = digitKeycodes[n] else { return }
    let src = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
    down?.flags = .maskControl
    let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
    up?.flags = .maskControl
    down?.post(tap: .cgSessionEventTap)
    up?.post(tap: .cgSessionEventTap)
}

/// 跳转到该显示器空间环中指定位置的桌面（⌃+位置号，位置号从 1 开始，即 ⌃+1=第 1 个）。
/// 发送后轮询确认真的到达目标空间（合成事件也可能被丢，失败自动重试）。
private func jumpToSpaceIndex(_ index: Int, identifier: String, ring: [UInt64]) -> Bool {
    let target = ring[index]
    for attempt in 0..<4 {
        postCtrlDigit(index + 1)
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
            if cgsDisplayCurrentSpace(identifier: identifier) == target {
                return true
            }
        }
        log("space scan: ctrl+\(index + 1) #\(attempt + 1) did not reach \(target) on \(identifier)")
    }
    return false
}

/// 扫描所有显示器的所有空间，返回目标应用所在的显示器（空间的归属存在该 display 结构里）。
/// 命中后系统停在该空间（光标保持在目标显示器）；找不到返回 nil，期间发生过的切换都已恢复。
/// 只扫空间数 >= 2 的显示器（单空间显示器无需切换）。
/// 跳转采用合成 ⌃+数字（用户需在系统设置里启用"键盘→快捷键→调度中心→切换桌面"），
/// 每次跳转是绝对定位（指定序号），不依赖连续滑动，因此不会累积误差。
func scanSpaceForApp(pid: pid_t, displays: [ManagedDisplay], uuidToDisplay: [String: CGDirectDisplayID]) -> CGSSpaceID? {
    let cursorOrigin = CGEvent(source: nil)?.location
    defer {
        if let c = cursorOrigin { _ = CGWarpMouseCursorPosition(c) }
    }

    for display in displays where display.spaceIDs.count >= 2 {
        guard let did = uuidToDisplay[display.identifier.lowercased()] else { continue }
        // 用实时值而非快照（currentSpaceID 可能过期）
        guard let original = cgsDisplayCurrentSpace(identifier: display.identifier) else { continue }
        let ring = display.spaceIDs
        guard let originalIdx = ring.firstIndex(of: original) else { continue }
        let count = ring.count

        warpCursorToDisplay(did)
        Thread.sleep(forTimeInterval: 0.08)

        // 从原桌面序号起，依次尝试其它序号，命中即停（留在目标桌面）
        var found: CGSSpaceID?
        for idx in 0..<count where idx != originalIdx {
            guard jumpToSpaceIndex(idx, identifier: display.identifier, ring: ring) else {
                log("space scan: stuck jumping to index \(idx) on \(display.identifier); abort this display")
                break
            }
            Thread.sleep(forTimeInterval: 0.2)   // 等窗口上屏
            if appOnScreen(pid: pid) {
                found = CGSSpaceID(ring[idx])
                log("space scan: found \(pid) on \(display.identifier) desktop \(idx + 1) space \(ring[idx])")
                break
            }
        }

        if found != nil {
            return found
        }

        // 未命中：跳回原桌面（绝对定位，可靠）
        if !jumpToSpaceIndex(originalIdx, identifier: display.identifier, ring: ring) {
            log("space scan: failed to restore \(display.identifier) to desktop \(originalIdx + 1) space \(original)")
        }
    }
    return nil
}

// MARK: - 桌面索引缓存（按需构建，切换后顺带温一次）
private var desktopIndex: [String: Set<pid_t>] = [:]
private let indexQueue = DispatchQueue(label: "eswitch.desktop-index")
private var indexLastBuilt = Date.distantPast

/// 索引是否足够新鲜、可信任。应用在桌面间移动后索引会过期，超时即弃用回退扫描。
private func indexFresh() -> Bool {
    Date().timeIntervalSince(indexLastBuilt) < 90
}

/// 重建索引并存入缓存。只在一次真实激活之后顺带调用（用户正处于切换情境），
/// 避免静默地在后台翻动用户的桌面。无权限或失败时保持旧缓存。
func warmDesktopIndex() {
    let now = Date()
    guard now.timeIntervalSince(indexLastBuilt) > 10 else { return }  // 防抖
    indexLastBuilt = now
    log("desktop index: warming (age \(now.timeIntervalSince(indexLastBuilt))s)")
    buildDesktopIndex { newIndex in
        indexQueue.sync { desktopIndex = newIndex }
        log("desktop index: warmed \(newIndex.count) entries")
    }
}

/// 跨虚拟桌面激活应用：当前空间可见则直接激活；否则后台查找桌面索引快速跳转；
/// 索引未命中时回退到实时逐格扫描。整个流程不阻塞 UI。
func activateApp(_ app: AppInfo) {
    guard let running = NSRunningApplication(processIdentifier: app.pid) else { return }

    // 当前空间可见 → 直接激活
    if appOnScreen(pid: app.pid) {
        running.activate(options: [.activateIgnoringOtherApps])
        return
    }

    // 无辅助功能权限时退化为普通激活
    guard AXIsProcessTrusted() else {
        running.activate(options: [.activateIgnoringOtherApps])
        return
    }

    DispatchQueue.global(qos: .userInitiated).async {
        let displays = managedDisplaySpaces()
        let uuidToDisplay = Dictionary(uniqueKeysWithValues: onlineDisplays().map { ($0.uuid.lowercased(), $0.displayID) })

        // 1) 用索引精确定位（仅当索引新鲜才可信）
        let snapshot = indexFresh() ? (indexQueue.sync { desktopIndex }) : [:]
        if let hit = locate(app.pid, in: snapshot),
           let did = uuidToDisplay[hit.display],
           let disp = displays.first(where: { $0.identifier.lowercased() == hit.display }),
           hit.desktopIndex < disp.spaceIDs.count {
            let ring = disp.spaceIDs
            log("activating \(app.name): index hit \(hit.display)@\(hit.desktopIndex) (space \(ring[hit.desktopIndex]))")
            warpCursorToDisplay(did)
            Thread.sleep(forTimeInterval: 0.08)
            if jumpToSpaceIndex(hit.desktopIndex, identifier: disp.identifier, ring: ring) {
                Thread.sleep(forTimeInterval: 0.4)
                running.activate(options: [.activateIgnoringOtherApps])
                return
            }
            log("activating \(app.name): index jump failed, fall back to scan")
        } else {
            log("activating \(app.name): no index hit, fall back to scan")
        }

        // 2) 索引未命中/失败 → 实时扫描
        guard let target = scanSpaceForApp(pid: app.pid, displays: displays, uuidToDisplay: uuidToDisplay) else {
            running.activate(options: [.activateIgnoringOtherApps])
            return
        }
        log("activating \(app.name): found on space \(target)")
        // 扫描结束时系统已停在该空间，稍等动画收尾再激活
        Thread.sleep(forTimeInterval: 0.4)
        running.activate(options: [.activateIgnoringOtherApps])
        // 顺带温一次索引，下次切换可单跳直达
        warmDesktopIndex()
    }
}

// MARK: - Self-test: 合成 ⌃+N 的序号语义（开发用 `--selftest-ctrl`）

func runCtrlSelfTest() {
    let displays = managedDisplaySpaces()
    for d in displays {
        let cur = cgsDisplayCurrentSpace(identifier: d.identifier)
        log("selftest: display \(d.identifier) current=\(String(describing: cur)) ring=\(d.spaceIDs)")
    }
    let beforeInternal = cgsDisplayCurrentSpace(identifier: displays[0].identifier)

    // 依次测 ⌃+1..6，观察每个数字会把内置/外接切到哪个空间
    for n in 1...6 {
        postCtrlDigit(n)
        Thread.sleep(forTimeInterval: 1.0)
        let curInt = displays.first.flatMap { cgsDisplayCurrentSpace(identifier: $0.identifier) }
        let curExt = displays.dropFirst().first.flatMap { cgsDisplayCurrentSpace(identifier: $0.identifier) }
        log("selftest: ctrl+\(n) -> internal=\(String(describing: curInt)) external=\(String(describing: curExt))")
    }

    // 恢复内置到最初
    if beforeInternal != nil {
        if let idx = displays[0].spaceIDs.firstIndex(of: beforeInternal!) {
            postCtrlDigit(idx + 1)
            Thread.sleep(forTimeInterval: 0.8)
        }
    }
    exit(0)
}