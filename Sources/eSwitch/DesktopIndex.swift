import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - 桌面索引（预扫描缓存）
// 思路：后台定期用合成的 ⌃+数字 依次跳遍每个显示器的每个桌面，记录每个桌面上
// 有哪些应用的窗口（pid → 桌面序号）。切换激活时先从索引定位目标桌面，⌃+N 一次
// 跳转过去即可，不必再做逐格扫描。
//
// 序号语义（macOS 实测）：⌃+数字 只作用于「光标所在显示器」的空间环，
// 且 N 对应空间环的下标 N-1（ring[0]→⌃+1, ring[1]→⌃+2, ...）。
// 所以索引按「显示器 identifier + 桌面序号」组织，跳转前先把光标移到对应显示器。

/// 建立应用 → 桌面序号 的索引。
/// 对每个显示器，先把光标移到其中心，然后依次 ⌃+1..N 每个桌面都停一下，
/// 枚举该桌面上所有 on-screen 应用的 pid，记录 (display, desktopIndex) → Set<pid>。
/// 完成后光标归位、并回到调用前的桌面。
/// 返回 dict：key = "displayUUID@desktopIndex"，value = pid 集合。
func buildDesktopIndex(completion: @escaping ([String: Set<pid_t>]) -> Void) {
    DispatchQueue.global(qos: .utility).async {
        let cursorOrigin = CGEvent(source: nil)?.location
        defer {
            if let c = cursorOrigin { _ = CGWarpMouseCursorPosition(c) }
        }

        var result: [String: Set<pid_t>] = [:]
        let displays = managedDisplaySpaces()
        let uuidToDisplay = Dictionary(uniqueKeysWithValues: onlineDisplays().map { ($0.uuid.lowercased(), $0.displayID) })
        guard !displays.isEmpty else { log("desktop index: no displays"); completion(result); return }

        // 记录每个显示器的起始桌面，最后恢复
        var originals: [String: Int] = [:]   // identifier -> original desktopIndex
        func readOriginalIdx(_ d: ManagedDisplay) -> Int? {
            guard let cur = cgsDisplayCurrentSpace(identifier: d.identifier) else { return nil }
            return d.spaceIDs.firstIndex(of: cur)
        }
        for d in displays {
            if let idx = readOriginalIdx(d) { originals[d.identifier] = idx }
        }
        log("desktop index: originals \(originals)")

        for d in displays {
            guard let did = uuidToDisplay[d.identifier.lowercased()] else {
                log("desktop index: no uuid match for \(d.identifier)")
                continue
            }
            guard !d.spaceIDs.isEmpty else { continue }

            warpCursorToDisplay(did)
            Thread.sleep(forTimeInterval: 0.08)
            log("desktop index: scanning \(d.identifier) (\(d.spaceIDs.count) spaces)")

            for (idx, _) in d.spaceIDs.enumerated() {
                postCtrlDigit(idx + 1)
                let deadline = Date().addingTimeInterval(1.5)
                while Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                    if cgsDisplayCurrentSpace(identifier: d.identifier) == d.spaceIDs[idx] { break }
                }
                Thread.sleep(forTimeInterval: 0.25)   // 等窗口上屏
                let key = "\(d.identifier.lowercased())@\(idx)"
                result[key] = pidsOnScreen(displayID: did)
                log("desktop index: space \(idx+1) → \(result[key]?.count ?? 0) pids")
            }
        }

        // 恢复各显示器原桌面
        for d in displays {
            guard let idx = originals[d.identifier] else { continue }
            if let did = uuidToDisplay[d.identifier.lowercased()] {
                warpCursorToDisplay(did)
                Thread.sleep(forTimeInterval: 0.08)
            }
            postCtrlDigit(idx + 1)
            Thread.sleep(forTimeInterval: 0.6)
        }

        completion(result)
    }
}

/// 落在指定显示器上的所有上屏窗口所属 pid 集合。
/// CGWindowList 的 .optionOnScreenOnly 会返回所有显示器的窗口，必须按窗口
/// 中心点所在显示器过滤，否则建索引时每个桌面都会记下全部窗口。
private func pidsOnScreen(displayID: CGDirectDisplayID) -> Set<pid_t> {
    guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
    let bounds = CGDisplayBounds(displayID)
    var set = Set<pid_t>()
    for info in raw {
        guard let pid = info[kCGWindowOwnerPID as String] as? Int,
              let wbounds = info[kCGWindowBounds as String] as? [String: Any],
              let x = wbounds["X"] as? CGFloat,
              let y = wbounds["Y"] as? CGFloat,
              let w = wbounds["Width"] as? CGFloat,
              let h = wbounds["Height"] as? CGFloat else { continue }
        let center = CGPoint(x: x + w / 2, y: y + h / 2)
        if bounds.contains(center) { set.insert(pid_t(pid)) }
    }
    return set
}

/// 按桌面索引定位某个 pid 所在的 (displayUUID, desktopIndex)。
/// 索引表未命中返回 nil。
func locate(_ pid: pid_t, in index: [String: Set<pid_t>]) -> (display: String, desktopIndex: Int)? {
    for (key, pids) in index {
        if pids.contains(pid) {
            // key = "uuid@index"
            let parts = key.split(separator: "@")
            if parts.count == 2, let idx = Int(parts[1]) {
                return (String(parts[0]), idx)
            }
        }
    }
    return nil
}