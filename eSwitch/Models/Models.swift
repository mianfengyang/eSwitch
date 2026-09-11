import AppKit
import Foundation

// MARK: - Panel Screen Mode
enum PanelScreenMode: String, CaseIterable {
    case mainScreen = "主屏幕"
    case followCursor = "跟随光标所在屏"
    
    var description: String { rawValue }
}

// MARK: - App Info
struct AppInfo {
    let id: String
    let name: String
    let icon: NSImage?
    let pid: pid_t
}

// MARK: - Global State
var currentApps: [AppInfo] = []
var currentIndex: Int = 0
var isVisible: Bool = false
var switchPanel: NSPanel?
var lastSelectedBundleID: String?
let cubeState = CubeStateModel()

class CubeStateModel: ObservableObject {
    @Published var index: Int = 0
    @Published var visible: Bool = false
    /// 字母跳转目标（环心）。nil = 跟随 index，无跳转行为。
    @Published var jumpIndex: Int?
    /// 同首字母候选（右侧邻位卡片高亮提示）
    @Published var candidates: [Int] = []
    /// 面板等比缩放系数：小屏上窗口缩小，内容同步 scaleEffect，避免裁剪
    @Published var scale: CGFloat = 1.0
}
