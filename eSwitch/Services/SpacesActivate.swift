import AppKit
import CoreGraphics
import Foundation

// MARK: - 激活（v1.4 起统一 open -a）
// 松键激活单纯执行 `open -a <应用真实路径>`（LaunchServices 激活，= 点击 Dock 图标语义；
// 用路径避免本地化显示名/注册名不一致的匹配坑，见 activateApp）：
//   - 应用有窗口 → 带到前台（窗口在当前桌面则无跳动感）；
//   - 窗口全在其他桌面 → 遵循系统 Mission Control「切换到某个应用程序时，
//     转到该应用已打开窗口的 Space」设置（默认开 → 切到窗口所在桌面）；
//   - 无窗口（进程活着但关光窗口）→ 触发系统 reopen 事件，应用按需开出窗口；
//   - 进程已不存在 → 重新启动（= Dock 图标行为）。
// 全程不依赖 AX 窗口判据，因此无窗应用不再需要过滤。
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

// MARK: - 激活

/// 打开/激活目标应用：单纯执行 `/usr/bin/open -a <应用真实路径>`（等价于 `open -a xxx.app`，= 点击 Dock 图标）。
///
/// 传 bundle 真实路径而非显示名：`open -a` 按 LaunchServices 注册名匹配，
/// 本地化显示名不可靠（实测本机 17 个应用中 9 个按显示名匹配失败：Safari/终端/Code/访达/App Store/图书/备忘录/系统设置/音乐）；
/// 路径口径 17/17 全部可打开（含 VS Code，其注册名与文件名不一致）。
/// 这条指令覆盖所有状态，无需任何额外逻辑：
///   - 无窗应用（进程在、窗口全关）→ reopen 事件开出窗口（实测生效）；
///   - 窗口在任意桌面 → 被激活（遵循系统 Dock 语义）；
///   - 进程已退出 → 重新启动。
/// 后台队列里跑，不阻塞 UI。
func activateApp(_ app: AppInfo) {
    // 主线程解析路径：松键瞬间 pid 刚经过列表刷新，此刻取 bundleURL 最可靠；取不到回退显示名
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
