import AppKit
import CoreGraphics

// MARK: - Window Preview
/// 窗口内容预览：CGWindowList 取窗口 → CGWindowListCreateImage 截图。
/// 需要「屏幕录制」权限；无权限/截图失败时返回 nil，卡片降级为 App 图标。
/// 每次呼出切换器时重新截图（实时预览），后台线程执行不阻塞呼出动画。
final class WindowPreviewProvider: ObservableObject {
    static let shared = WindowPreviewProvider()

    @Published var previews: [String: NSImage] = [:]   // AppInfo.id -> 最前窗口预览
    @Published var granted = false                       // 屏幕录制权限状态

    /// 关闭预览时清空显示，卡片回到 App 图标
    func clear() {
        DispatchQueue.main.async { [weak self] in
            self?.previews = [:]
        }
    }

    /// 启动时调用一次：请求屏幕录制权限（未授权时系统弹授权框，和辅助功能权限同机制）
    func requestPermission() {
        if #available(macOS 14.0, *) {
            granted = CGRequestScreenCaptureAccess()
        } else {
            granted = true
        }
        log("Screen recording permission: \(granted)")
    }

    /// 打开设置时调用：静默检查授权状态（不弹框），授权后回来能看到状态变化
    func preflight() {
        if #available(macOS 14.0, *) {
            granted = CGPreflightScreenCaptureAccess()
        }
        log("Screen recording preflight: \(granted)")
    }

    /// 刷新所有应用的最前窗口预览（后台线程执行，主线程更新 UI）
    func refresh(apps: [AppInfo]) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard self.granted else { return }

            // 列出全部正常层窗口，数组序即 z 序（索引越小越靠前）
            let opts: CGWindowListOption = [.optionOnScreenOnly]
            guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return }

            var result: [String: NSImage] = [:]

            for app in apps {
                // 该应用最靠前的可见窗口
                var bestID: CGWindowID?
                var bestOrder = Int.max
                for (i, info) in raw.enumerated() where i < bestOrder {
                    let pid = (info[kCGWindowOwnerPID as String] as? Int) ?? -1
                    let layer = (info[kCGWindowLayer as String] as? Int) ?? 0
                    guard pid == Int(app.pid), layer == 0 else { continue }
                    // 跳过 1×1 的占位窗口（某些应用有隐藏 helper 窗口）
                    if let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                       bounds["Width"] ?? 0 < 8, bounds["Height"] ?? 0 < 8 { continue }
                    bestID = (info[kCGWindowNumber as String] as? Int).map(CGWindowID.init)
                    bestOrder = i
                }
                guard let id = bestID else { continue }

                let options = CGWindowImageOption([.boundsIgnoreFraming, .bestResolution])
                guard let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, id, options) else { continue }
                let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                result[app.id] = img
            }

            let g = result
            DispatchQueue.main.async {
                self.previews = g
            }
        }
    }
}
