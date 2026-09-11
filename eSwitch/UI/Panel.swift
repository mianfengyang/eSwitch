import AppKit
import SwiftUI

// MARK: - Panel Screen Helper
func getTargetScreen() -> NSScreen {
    switch SettingsManager.shared.panelScreenMode {
    case .mainScreen:
        // NSScreen.main tracks the cursor, so use screens.first for a stable primary display
        return NSScreen.screens.first ?? NSScreen.main ?? NSScreen.screens[0]
    case .followCursor:
        let location = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            if NSMouseInRect(location, screen.frame, false) {
                return screen
            }
        }
        // Fallback to main if cursor not found on any screen
        return NSScreen.main ?? NSScreen.screens[0]
    }
}

// MARK: - Panel
class SwitchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 透明背景托管视图：NSHostingView 默认按窗口背景色（系统灰）填充整个矩形 frame，
/// 圆角(24pt)之外四角会透出灰底。重写 isOpaque 并设 layer 背景为透明，让圆角外完全透出。
final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = .clear
    }
}

// MARK: - Show / Hide
func showSwitcher() {
    log("showSwitcher")
    currentApps = getApps()
    guard !currentApps.isEmpty else { log("no apps"); return }
    
    // 尝试从上次选择的位置开始
    var startIndex = 0
    if let lastID = lastSelectedBundleID {
        if let idx = currentApps.firstIndex(where: { $0.id == lastID }) {
            startIndex = idx
        }
    }
    
    cubeState.index = startIndex
    cubeState.jumpIndex = nil
    cubeState.candidates = []
    currentIndex = startIndex
    isVisible = true
    cubeState.visible = true
    
    if switchPanel == nil {
        let panel = SwitchPanel(
            contentRect: NSRect(x: 0, y: 0, width: Theme.panelWidth, height: Theme.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true  // 系统阴影贴合内容圆角轮廓生成（同系统 cmd-tab 切换器）
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentView = TransparentHostingView(rootView: SwitcherView(state: cubeState))
        switchPanel = panel
    }

    // Always reposition when showing (settings may have changed)
    let screen = getTargetScreen()
    let sf = screen.visibleFrame
    // 面板可能需要大于屏幕：等比缩放到屏幕 95% 内，内容同步 scaleEffect 避免裁剪
    let s = min(1.0, sf.width * 0.95 / Theme.panelWidth, sf.height * 0.95 / Theme.panelHeight)
    cubeState.scale = s
    let sw = Theme.panelWidth * s
    let sh = Theme.panelHeight * s
    switchPanel?.setFrame(NSRect(x: sf.midX - sw / 2, y: sf.midY - sh / 2, width: sw, height: sh), display: true)
    
    switchPanel?.orderFront(nil)
}

func hideSwitcher(activate: Bool = true) {
    log("hideSwitcher(activate: \(activate))")
    isVisible = false
    cubeState.visible = false
    switchPanel?.orderOut(nil)
    
    if activate {
        // 字母定位后环心与 index 可能不同步，以环心为准激活
        let idx = cubeState.jumpIndex ?? currentIndex
        if !currentApps.isEmpty, idx >= 0, idx < currentApps.count {
            let target = currentApps[idx]
            lastSelectedBundleID = target.id
            activateApp(target)
        }
    }
}

func rotateNext() {
    guard !currentApps.isEmpty else { return }
    // 普通旋转退出字母定位态，否则环心渲染仍被 jumpIndex 压住
    if cubeState.jumpIndex != nil {
        cubeState.jumpIndex = nil
        cubeState.candidates = []
        log("jump state cleared by rotation")
    }
    currentIndex = (currentIndex + 1) % currentApps.count
    cubeState.index = currentIndex
    log("rotate -> \(currentIndex): \(currentApps[currentIndex].name)")
}

func rotatePrev() {
    guard !currentApps.isEmpty else { return }
    if cubeState.jumpIndex != nil {
        cubeState.jumpIndex = nil
        cubeState.candidates = []
        log("jump state cleared by rotation")
    }
    currentIndex = (currentIndex - 1 + currentApps.count) % currentApps.count
    cubeState.index = currentIndex
    log("rotate <- \(currentIndex): \(currentApps[currentIndex].name)")
}

// MARK: - Letter Jump（快速定位）
/// 计算首字母匹配的下标列表（纯函数，可单测）
func letterMatchIndices(names: [String], letter: String) -> [Int] {
    names.indices.filter { names[$0].switcherInitial == letter }
}

/// 按住呼出修饰键按字母 → 对应应用跳到环心；同字母多个时其余的作候选（原位高亮角标）。
/// 已定位到该字母的某个应用 → 再按同字母在匹配列表中轮换。
func jumpToLetter(_ letter: Character) {
    guard !currentApps.isEmpty else { return }
    let up = letter.uppercased()
    let matches = letterMatchIndices(names: currentApps.map(\.name), letter: up)
    guard let first = matches.first else {
        log("jump '\(up)': no match")
        return
    }
    // 已定位到该字母的某个应用 → 轮换到下一个；否则定位到第一个
    let next: Int
    if let cur = cubeState.jumpIndex, let pos = matches.firstIndex(of: cur) {
        next = matches[(pos + 1) % matches.count]
    } else {
        next = first
    }
    let others = matches.filter { $0 != next }
    DispatchQueue.main.async {
        cubeState.jumpIndex = next
        cubeState.candidates = Array(others.prefix(2))
        cubeState.index = next
        currentIndex = next
        log("jump '\(up)' -> \(next): \(currentApps[next].name) (matches: \(matches.map { currentApps[$0].name }))")
    }
}
