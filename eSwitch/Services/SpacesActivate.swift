import AppKit
import CoreGraphics
import Foundation

// MARK: - 激活（v1.5 Finder 恢复 AppleScript）
// 激活策略：
//   - Finder（com.apple.finder）：AppleScript "tell application Finder to activate"
//     因为 Finder 是系统进程，open -a 在跨 Space 时无法将窗口拉回当前 Space，
//     AppleScript 才能可靠 bring Finder 到当前 Space 并前置窗口。
//   - 其它应用：单纯执行 `open -a <应用真实路径>`（LaunchServices 激活，= 点击 Dock 图标）。
//     用路径避免本地化显示名/注册名不一致的匹配坑，路径口径 17/17 全部可打开。
//     覆盖状态：有窗口→前台、跨空间→open -a 会遵循系统行为、无窗→reopen、进程退出→重启。
// 下方保留纯查询工具（空间环 / 当前空间），供桌面索引与自检使用。

func cgsSymbol(_ name: String) -> UnsafeMutableRawPointer? {
    dlsym(dlopen(nil, RTLD_NOW), name)
}

func cgsMainConnectionID() -> Int32 {
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
/// （替代已过时的 plist 路径），macOS 26 实测可用。纯查询，不切换空间。
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

/// Finder bundle identifier — 系统进程，需 AppleScript 激活才能跨 Space 拉回当前 Space。
private let kFinderBundleID = "com.apple.finder"

// MARK: - 激活

/// 打开/激活目标应用：
///   - Finder → AppleScript（open -a 在跨 Space 时无法拉回 Finder 窗口）
///   - 其它应用 → `open -a <路径>`
func activateApp(_ app: AppInfo) {
    if app.id == kFinderBundleID {
        activateFinderViaAppleScript()
        return
    }
    // 非 Finder：走 open -a 策略
    let path = NSRunningApplication(processIdentifier: app.pid)?.bundleURL?.path
    let target = (path != nil && FileManager.default.fileExists(atPath: path!)) ? path! : app.name
    let name = app.name
    DispatchQueue.global(qos: .userInitiated).async {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", target]
        do {
            try task.run()
            task.waitUntilExit()
            log("activating \(name): open -a '\(target)' exit=\(task.terminationStatus)")
        } catch {
            log("activating \(name): open -a '\(target)' failed: \(error.localizedDescription)")
        }
    }
}

/// Finder 专属激活：用 osascript + AppleScript 让 Finder bring itself forward。
/// Finder 是系统进程，NSRunningApplication.activate / open -a 在跨 Space 时
/// 无法将窗口拉回当前 Space，AppleScript 才能可靠激活。
private func activateFinderViaAppleScript() {
    DispatchQueue.global(qos: .userInitiated).async {
        // Finder 在后台时可能需先确保运行
        if let finderURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: kFinderBundleID) {
            NSWorkspace.shared.openApplication(at: finderURL, configuration: NSWorkspace.OpenConfiguration())
        }
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", "tell application \"Finder\" to activate"]
        task.launch()
        task.waitUntilExit()
        log("Finder activated: exitCode=\(task.terminationStatus)")
    }
}
