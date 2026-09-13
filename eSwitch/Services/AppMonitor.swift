import AppKit
import Foundation

// MARK: - AppMonitor（常驻应用缓存 + 生命周期通知）
//
// NSWorkspace 的 didLaunch / didTerminate 是系统推送，零权限、零轮询开销：
//   - 任何 .regular GUI 应用启动/退出（⌘Q、崩溃、被杀）瞬间更新缓存
//   - 切换器呼出直接读缓存（不再全量枚举 runningApplications）
//
// 兜底机制：每次呼出强制一次全量重建，任何漏接的通知（极端时序）
// 最多存活一次呼出周期，不会把缓存弄脏。
//
// 线程模型：缓存由 appQueue 上的串行队列独占保护，读写都过队列。
// showSwitcher 在主线程调用，用 sync 一次同步重建后回主线程使用。

private let appQueue = DispatchQueue(label: "eswitch.appmonitor")

final class AppMonitor {
    static let shared = AppMonitor()

    /// 当前缓存列表（仅 appQueue 线程访问，外部一律经 refresh() 取）。
    private(set) var apps: [AppInfo] = []

    /// 启动时注册 NSWorkspace 生命周期通知。在 app.run() 之前调用。
    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: nil) { [weak self] note in
            self?.handleLaunch(note)
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: nil) { [weak self] note in
            self?.handleTerminate(note)
        }
        appQueue.sync {
            rebuild()
        }
        log("AppMonitor: started, \(apps.count) apps cached")
    }

    /// 刷新缓存（全量重建），返回最新列表。调用线程无关（内部跳转 appQueue，sync 等待结果）。
    func refresh() -> [AppInfo] {
        appQueue.sync {
            rebuild()
            return apps
        }
    }

    // MARK: - 通知处理

    private func handleLaunch(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        guard app.activationPolicy == .regular else { return }   // 只跟踪常规 GUI 应用
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return }  // 不跟踪自己
        appQueue.sync {
            guard let idx = apps.firstIndex(where: { $0.id == app.bundleIdentifier }) else {
                add(app: app)
                return
            }
            // 同名 bundle 重启（pid 变化）：换新条目，保留位置
            apps[idx] = makeInfo(app: app, name: apps[idx].name, englishName: apps[idx].englishName)
            log("AppMonitor: relaunched \(apps[idx].name) pid=\(app.processIdentifier)")
        }
    }

    private func handleTerminate(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        appQueue.sync {
            // 同一 bundle 可能有多进程实例（极少见），全删
            let before = apps.count
            apps.removeAll { $0.id == app.bundleIdentifier }
            if apps.count != before {
                log("AppMonitor: terminated \(app.localizedName ?? "pid \(app.processIdentifier)")  缓存 \(before) → \(apps.count)")
            }
        }
    }

    // MARK: - 构建

    private func rebuild() {
        let fresh = getApps()
        apps = fresh
        log("AppMonitor: rebuild \(apps.count) apps")
    }

    private func add(app: NSRunningApplication) {
        guard let name = app.localizedName else { return }
        apps.append(makeInfo(app: app, name: name, englishName: name))
        log("AppMonitor: launched \(name) pid=\(app.processIdentifier)  缓存 → \(apps.count)")
    }

    /// NSRunningApplication → AppInfo（英文名取 Info.plist 原始值，与 getApps 同口径）。
    func makeInfo(app: NSRunningApplication, name: String, englishName: String) -> AppInfo {
        var english = englishName
        if let url = app.bundleURL {
            let plistPath = url.appendingPathComponent("Contents/Info.plist")
            if let dict = NSDictionary(contentsOf: plistPath) as? [String: Any] {
                for key in ["CFBundleDisplayName", "CFBundleName"] {
                    if let v = dict[key] as? String, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        english = v
                        break
                    }
                }
            }
        }
        return AppInfo(id: app.bundleIdentifier ?? UUID().uuidString, name: name, englishName: english, icon: app.icon, pid: app.processIdentifier)
    }
}
