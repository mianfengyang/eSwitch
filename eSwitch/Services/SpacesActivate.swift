import AppKit
import CoreGraphics
import Foundation

// MARK: - Spaces（虚拟桌面）—— 仅纯查询，不切换桌面
// macOS 26 上 CGS 直接切换空间的私有符号（CGSSwitchToSpace 等）已被移除，
// 本项目不再合成按键跳转桌面：跨空间激活统一交给系统原生 activateAllWindows
// （=Cmd+Tab 语义：把目标应用在所有 Space 的窗口拉回当前 Space 并前置）。
// 以下仅保留纯查询工具（空间环 / 当前空间 / 上屏检测），供桌面索引与自检使用。

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

/// 应用当前是否有窗口显示在屏幕上（即位于当前空间）
func appOnScreen(pid: pid_t) -> Bool {
    guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return true }
    return raw.contains { ($0[kCGWindowOwnerPID as String] as? Int) == Int(pid) }
}

// MARK: - 跨虚拟桌面激活（不跳桌面）

/// Finder bundle identifier — 系统进程，必须走 AppleScript 激活
private let kFinderBundleID = "com.apple.finder"

/// 跨虚拟桌面激活应用：当前空间可见则直接激活；否则用系统原生 activateAllWindows
/// 把窗口拉回当前 Space（=Cmd+Tab 语义），失败退化为普通激活。
/// 全程不跳转任何桌面，不阻塞 UI。
func activateApp(_ app: AppInfo) {
    // Finder 是系统进程，NSRunningApplication.activate 对它无效（静默忽略）
    // 必须用 AppleScript "tell application 'Finder' to activate" 才能 bring-to-front
    if app.id == kFinderBundleID {
        activateFinder()
        return
    }

    guard let running = NSRunningApplication(processIdentifier: app.pid) else { return }

    // 当前空间可见 → 直接激活
    if appOnScreen(pid: app.pid) {
        running.activate(options: [.activateIgnoringOtherApps])
        return
    }

    DispatchQueue.global(qos: .userInitiated).async {
        // —— eSwitch 方案：跨空间激活直接交给系统原生 activateAllWindows
        // （=Cmd+Tab 语义：把目标应用在所有 Space 的窗口拉回当前 Space 并前置），
        // 不跳桌面，从根上消除跳桌面/合成按键竞态。
        let activateOptions: NSApplication.ActivationOptions = {
            if #available(macOS 14.0, *) {
                return [.activateAllWindows]
            }
            return [.activateAllWindows, .activateIgnoringOtherApps]
        }()
        if running.activate(options: activateOptions) {
            for _ in 0..<6 { // 激活异步生效，最多轮询 ~1.2s 等窗口上屏
                if appOnScreen(pid: app.pid) {
                    log("activating \(app.name): eSwitch activateAllWindows 生效（窗口拉回当前 Space）")
                    return
                }
                Thread.sleep(forTimeInterval: 0.2)
            }
            log("activating \(app.name): eSwitch activateAllWindows 调用后仍无窗口上屏，退化为普通激活")
        } else {
            log("activating \(app.name): eSwitch activateAllWindows 调用失败，退化为普通激活")
        }
        // 兜底：普通激活（仅切换应用激活状态；窗口若在他 Space 则保持原处）
        running.activate(options: [.activateIgnoringOtherApps])
    }
}

/// Finder 专属激活：用 osascript + AppleScript 让 Finder bring itself forward。
/// NSRunningApplication.activate() 对 Finder 无效（Finder 是系统进程，忽略此调用）。
/// 不跳桌面：Finder 窗口保持在其所在 Space，仅切换激活状态。
private func activateFinder() {
    DispatchQueue.global(qos: .userInitiated).async {
        // Finder 在后台时可能需要先启动（非弃用 API：openApplication）
        if let finderURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: kFinderBundleID) {
            NSWorkspace.shared.openApplication(at: finderURL, configuration: NSWorkspace.OpenConfiguration())
        }
        // 用 AppleScript 可靠激活
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", "tell application \"Finder\" to activate"]
        task.launch()
        task.waitUntilExit()
        log("Finder activated: exitCode=\(task.terminationStatus)")
    }
}
