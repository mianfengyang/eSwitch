import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - 桌面索引（应用 pid → (显示器, 桌面序号)）
// 思路：给「应用 pid → (显示器, 桌面序号)」建索引，激活时单跳直达。
// 原按桌面翻页扫描会静默切换用户桌面（体验问题），故改用 CGS 私有 API
// CGSCopyWindowsWithOptionsForSpace 直接按空间枚举窗口——完全不切桌面。
//
// 序号语义（macOS 实测）：⌃+数字 只作用于「光标所在显示器」的空间环，
// 且 N 对应空间环的下标 N-1（ring[0]→⌃+1, ring[1]→⌃+2, ...）。
// 所以索引按「显示器 identifier + 桌面序号」组织，跳转前先把光标移到对应显示器。

/// 窗口所属的空间 id 列表（CGS 私有 API CGSCopySpacesForWindows，纯查询不切桌面）。
/// selector 0x3F = 全部窗口类别（桌面/全屏/系统/隐藏/完整/所有，实测 0x35 覆盖不全）。
private func spacesOfWindow(_ windowID: CGWindowID, conn: Int32) -> [UInt64] {
    typealias Fn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    guard let s = cgsSymbol("CGSCopySpacesForWindows") else { return [] }
    let f = unsafeBitCast(s, to: Fn.self)
    let arr = [windowID] as CFArray
    guard let r = f(conn, 0x3F, arr)?.takeRetainedValue() as? [NSNumber] else { return [] }
    return r.map { $0.uint64Value }
}

/// 所有窗口 id → 所属 pid 的映射（含 off-screen 窗口，供按空间归属换算 pid）。
private func windowIDToPID() -> [CGWindowID: pid_t] {
    guard let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [:] }
    var map: [CGWindowID: pid_t] = [:]
    for info in raw {
        guard let wid = info[kCGWindowNumber as String] as? Int,
              let pid = info[kCGWindowOwnerPID as String] as? Int else { continue }
        map[CGWindowID(wid)] = pid_t(pid)
    }
    return map
}

/// 建立 应用 pid → 桌面 的索引（纯查询，不切换任何桌面、不动光标）。
/// 对每个窗口用 CGSCopySpacesForWindows 查询它属于哪些空间，再按空间环换算成
/// (显示器, 桌面序号)。key = "displayUUID(小写)@desktopIndex"，value = pid 集合。
func buildDesktopIndexSilent() -> [String: Set<pid_t>] {
    var result: [String: Set<pid_t>] = [:]
    let displays = managedDisplaySpaces()
    guard !displays.isEmpty else { return result }
    let conn = cgsMainConnectionID()

    // spaceID → (displayLower, desktopIndex)
    var spaceToSlot: [UInt64: (String, Int)] = [:]
    for d in displays {
        for (idx, spaceID) in d.spaceIDs.enumerated() {
            spaceToSlot[spaceID] = (d.identifier.lowercased(), idx)
        }
    }

    for (wid, pid) in windowIDToPID() {
        for spaceID in spacesOfWindow(wid, conn: conn) {
            guard let slot = spaceToSlot[spaceID] else { continue }
            result["\(slot.0)@\(slot.1)", default: []].insert(pid)
        }
    }
    return result
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

/// Self-test: 验证 CGSCopyWindowsWithOptionsForSpace 能正确枚举各空间窗口。
/// 对每一显示器：打印各空间窗口 pid 数量，并与「当前空间实际 on-screen 窗口」对比，
/// 校验索引准确性（开发用 `--selftest-index`）。
func runIndexSelfTest() {
    let index = buildDesktopIndexSilent()
    let displays = managedDisplaySpaces()
    var keysByDisplay: [String: [String]] = [:]
    for key in index.keys {
        let display = String(key.split(separator: "@").first ?? "")
        keysByDisplay[display, default: []].append(key)
    }
    for d in displays {
        let low = d.identifier.lowercased()
        let keys = keysByDisplay[low]?.sorted() ?? []
        let cur = cgsDisplayCurrentSpace(identifier: d.identifier)
        guard let curIdx = d.spaceIDs.firstIndex(of: cur ?? 0) else { continue }
        let onScreenPids = currentOnScreenPids()
        for key in keys {
            let idx = Int(key.split(separator: "@")[1]) ?? -1
            let silent = index[key] ?? []
            let marked = idx == curIdx ? " *current*" : ""
            log("index selftest: space\(idx + 1)\(marked) → \(silent.count) app pids")
            if idx == curIdx {
                let overlap = silent.intersection(onScreenPids).count
                log("index selftest:   onScreen=\(onScreenPids.count) overlap=\(overlap)")
            }
        }
    }
    log("index selftest: done, \(index.count) entries")
}

/// 当前所有上屏窗口所属 pid（跨显示器）
private func currentOnScreenPids() -> Set<pid_t> {
    guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
    var set = Set<pid_t>()
    for info in raw {
        if let pid = info[kCGWindowOwnerPID as String] as? Int { set.insert(pid_t(pid)) }
    }
    return set
}