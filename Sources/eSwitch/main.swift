import AppKit
import CoreGraphics
import SwiftUI
import ServiceManagement
import ApplicationServices

func log(_ msg: String) {
    let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    let line = "[\(ts)] \(msg)\n"
    let path = "/tmp/eswitch_debug.log"
    if let data = line.data(using: .utf8) {
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}

// MARK: - Panel Screen Mode
enum PanelScreenMode: String, CaseIterable {
    case mainScreen = "主屏幕"
    case followCursor = "跟随光标所在屏"
    
    var description: String { rawValue }
}

// MARK: - Hotkey
struct Hotkey: Codable, Equatable {
    /// 修饰键掩码: 1=⌘, 2=⇧, 4=⌥, 8=⌃
    var modifiers: Int
    /// 虚拟按键码（物理键位，与键盘布局无关）
    var keyCode: Int
    /// 显示名称（录制时按当前键盘布局获取，仅用于展示）
    var displayName: String
    
    static let command = 1
    static let shift = 2
    static let option = 4
    static let control = 8
    
    static let escKeyCode = 53
    
    static let defaultShow = Hotkey(modifiers: command, keyCode: escKeyCode, displayName: "esc")
    static let defaultPrev = Hotkey(modifiers: command | shift, keyCode: escKeyCode, displayName: "esc")
    
    /// 修饰键符号，按 macOS 习惯顺序：⌃ ⌥ ⇧ ⌘
    var modifierString: String {
        var s = ""
        if modifiers & Self.control != 0 { s += "⌃" }
        if modifiers & Self.option != 0 { s += "⌥" }
        if modifiers & Self.shift != 0 { s += "⇧" }
        if modifiers & Self.command != 0 { s += "⌘" }
        return s
    }
    
    /// 完整显示文本，如 "⌘ esc"
    var displayString: String {
        guard !modifierString.isEmpty else { return displayName }
        return modifierString + " " + displayName
    }
    
    /// 「选择应用」行的提示文本
    var releaseHint: String {
        guard !modifierString.isEmpty else { return "松开修饰键" }
        if modifierString.count == 1 { return "松开 \(modifierString) 键" }
        return "松开全部修饰键（\(modifierString)）"
    }
    
    /// 把 NSEvent 修饰键转成掩码
    static func mask(_ flags: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if flags.contains(.command) { m |= command }
        if flags.contains(.shift) { m |= shift }
        if flags.contains(.option) { m |= option }
        if flags.contains(.control) { m |= control }
        return m
    }
    
    /// 把 CGEvent 修饰键转成掩码
    static func mask(_ flags: CGEventFlags) -> Int {
        var m = 0
        if flags.contains(.maskCommand) { m |= command }
        if flags.contains(.maskShift) { m |= shift }
        if flags.contains(.maskAlternate) { m |= option }
        if flags.contains(.maskControl) { m |= control }
        return m
    }
    
    /// 特殊按键的显示名（不依赖键盘布局）
    static let specialKeyNames: [Int: String] = [
        36: "↩",      // Return
        48: "⇥",      // Tab
        49: "Space",  // Space
        51: "⌫",      // Delete (Backspace)
        53: "esc",    // Escape
        63: "fn",     // Function
        64: "F17",
        76: "↩",      // Keypad Enter
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 105: "F13", 106: "F16", 107: "F14", 109: "F10",
        110: "菜单", 114: "帮助", 115: "Home", 116: "PgUp", 117: "⌦",
        118: "F4", 119: "End", 120: "F2", 121: "PgDn", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
    
    /// 生成按键显示名：优先特殊键表，其次取录制时的按键字符
    static func displayName(for keyCode: Int, characters: String?) -> String {
        if let special = specialKeyNames[keyCode] { return special }
        if let ch = characters?.first, ch.isASCII, ch >= " " {
            return ch.uppercased()
        }
        if let ch = characters, ch.count == 1,
           let sc = ch.unicodeScalars.first, sc.value >= 0x21, sc.value != 0x7F {
            return ch
        }
        return "Key \(keyCode)"
    }
}

// MARK: - Theme
/// 中性灰玻璃主题。卡片描边/选中光环使用系统强调色（跟随用户系统主题）。
/// v1.4: 面板整体 3 倍尺寸（适配 26 系统大屏），形状/比例不变。
enum Theme {
    static let accent = Color.accentColor
    static let panelRadius: CGFloat = 72      // 24 × 3
    static let cardRadius: CGFloat = 48       // 16 × 3
    static let dimText = Color.white.opacity(0.55)
    static let dimmerText = Color.white.opacity(0.4)
    // 面板固定尺寸
    static let panelWidth: CGFloat = 1260     // 420 × 3
    static let panelHeight: CGFloat = 810     // 270 × 3
    static let cardWidth: CGFloat = 272       // 240 → 272，卡片整体放大
    static let cardHeight: CGFloat = 292      // 264 → 292，卡片整体放大
    static let slotWidth: CGFloat = 330       // 312 → 330，配合更宽卡片
    static let cardAreaHeight: CGFloat = 478  // 450 → 478，给更大的卡片留高度
}

// MARK: - Glass Background (NSVisualEffectView)
final class GlassBackground: NSView {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    private let effect = NSVisualEffectView()

    init(material: NSVisualEffectView.Material = .hudWindow,
         blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
         state: NSVisualEffectView.State = .active) {
        self.material = material
        self.blendingMode = blendingMode
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = .clear

        effect.material = material
        effect.blendingMode = blendingMode
        effect.state = state
        effect.isEmphasized = true
        effect.wantsLayer = true
        effect.layer?.backgroundColor = .clear
        // 关键：behindWindow 模糊由系统合成器在窗口层绘制，view 自己的
        // cornerRadius / masksToBounds 截不到它，四角会露出直角灰底。
        // 唯一可靠做法是给 effect 设 maskImage（随尺寸动态重建）。
        effect.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effect)
        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: trailingAnchor),
            effect.topAnchor.constraint(equalTo: topAnchor),
            effect.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        updateMask()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layer?.masksToBounds = true
        updateMask()
    }

    /// 重建圆角蒙版，让 behindWindow 模糊严格限定在圆角内，四角完全透明。
    private func updateMask() {
        let b = bounds
        guard b.width > 1, b.height > 1 else {
            effect.maskImage = nil
            return
        }
        let radius = Theme.panelRadius
        let img = NSImage(size: b.size, flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        effect.maskImage = img
    }
}

/// 圆角玻璃容器：模糊层 + 半透明描边 + 顶部高光
struct GlassContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(
                ZStack {
                    GlassBackgroundView()
                        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
                    GlassDimOverlay()
                }
            )
            // 面板投影：先画圆角矩形再取其阴影，投影沿圆角轮廓生成。
            // 不能直接对上面的 ZStack 用 .shadow() —— 内含 NSViewRepresentable 模糊视图时
            // 按矩形边界投影，四角会露出直角阴影。
            .background(
                RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(0.55), radius: 84, x: 0, y: 42)
                    .shadow(color: .black.opacity(0.30), radius: 30, x: 0, y: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.28), .white.opacity(0.02), .clear],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
    }
}

/// SwiftUI 用的毛玻璃背景包装
struct GlassBackgroundView: NSViewRepresentable {
    func makeNSView(context: Context) -> GlassBackground { GlassBackground() }
    func updateNSView(_ nsView: GlassBackground, context: Context) {}
}

/// 玻璃面板的深色叠层：hudWindow 材质偏浅，压一层半透明黑把底色压深、白字/白描边立刻跳出来
struct GlassDimOverlay: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
            .fill(Color.black.opacity(0.42))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.12), .clear, .black.opacity(0.22)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
    }
}

// MARK: - Highlight Border
/// 中间卡片边框：静态白色高亮描边
struct HighlightBorder: View {
    var lineWidth: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .path(in: rect)
                .stroke(Color.white.opacity(0.75), lineWidth: lineWidth)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Settings Manager
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            setLaunchAtLogin(launchAtLogin)
        }
    }
    
    @Published var panelScreenMode: PanelScreenMode {
        didSet {
            UserDefaults.standard.set(panelScreenMode.rawValue, forKey: "panelScreenMode")
        }
    }
    
    @Published var showHotkey: Hotkey {
        didSet {
            saveHotkey(showHotkey, key: "hotkeyShow")
        }
    }
    
    @Published var prevHotkey: Hotkey {
        didSet {
            saveHotkey(prevHotkey, key: "hotkeyPrev")
        }
    }
    
    @Published var windowPreview: Bool {
        didSet {
            UserDefaults.standard.set(windowPreview, forKey: "windowPreview")
            if !windowPreview {
                WindowPreviewProvider.shared.clear()
            }
        }
    }
    
    private init() {
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        // 窗口预览默认开；无屏幕录制权限时启动探测会关掉它
        self.windowPreview = UserDefaults.standard.object(forKey: "windowPreview") as? Bool ?? true
        if let savedRaw = UserDefaults.standard.string(forKey: "panelScreenMode"),
           let mode = PanelScreenMode(rawValue: savedRaw) {
            self.panelScreenMode = mode
        } else {
            self.panelScreenMode = .mainScreen  // default: main screen
        }
        self.showHotkey = Self.loadHotkey(key: "hotkeyShow", fallback: .defaultShow)
        self.prevHotkey = Self.loadHotkey(key: "hotkeyPrev", fallback: .defaultPrev)
    }
    
    private static func loadHotkey(key: String, fallback: Hotkey) -> Hotkey {
        guard let data = UserDefaults.standard.data(forKey: key),
              let hk = try? JSONDecoder().decode(Hotkey.self, from: data) else {
            return fallback
        }
        return hk
    }
    
    private func saveHotkey(_ hk: Hotkey, key: String) {
        if let data = try? JSONEncoder().encode(hk) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    private func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                log("Launch at login error: \(error)")
            }
        } else {
            SMLoginItemSetEnabled((Bundle.main.bundleIdentifier ?? "") as CFString, enabled)
        }
    }
}

// MARK: - App Info
struct AppInfo {
    let id: String
    let name: String
    let icon: NSImage?
    let pid: pid_t
}

/// 应用是否有至少一个可见窗口（AX 查询，辅助功能权限下可用；
/// 无权限时保守返回 true，宁可多列不漏列）
func appHasWindows(pid: pid_t) -> Bool {
    guard AXIsProcessTrusted() else { return true }
    let appElement = AXUIElementCreateApplication(pid)
    var windowsRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
          let windows = windowsRef as? [AXUIElement] else { return true }
    for window in windows {
        var mainRef: CFTypeRef?
        var focusedRef: CFTypeRef?
        // 只认真正可见的窗口：main 或 focused（排除后台隐藏窗口）
        let isMain = AXUIElementCopyAttributeValue(window, kAXMainAttribute as CFString, &mainRef) == .success
            && (mainRef as? Bool ?? false)
        let isFocused = AXUIElementCopyAttributeValue(window, kAXFocusedAttribute as CFString, &focusedRef) == .success
            && (focusedRef as? Bool ?? false)
        if isMain || isFocused { return true }
    }
    // 窗口存在但没有 main/focused 标记的（如被其他全屏应用遮挡时的普通窗口），
    // 仍算可用，避免误杀
    return !windows.isEmpty
}

func getApps() -> [AppInfo] {
    NSWorkspace.shared.runningApplications.filter { app in
        // 1) 只列常规 GUI 应用，排除 eSwitch 自身（.accessory）
        app.activationPolicy == .regular &&
        app.bundleIdentifier != Bundle.main.bundleIdentifier &&
        // 2) 排除正在退出的进程（"没退干净"的僵尸状态）
        !app.isTerminated &&
        // 3) 排除 ⌘H 隐藏的应用
        !app.isHidden &&
        // 4) 兜底：进程活着但没有任何可用窗口的，不列
        appHasWindows(pid: app.processIdentifier)
    }.compactMap { app in
        guard let name = app.localizedName else { return nil }
        return AppInfo(id: app.bundleIdentifier ?? UUID().uuidString, name: name, icon: app.icon, pid: app.processIdentifier)
    }
}

// MARK: - Spaces (Virtual Desktops)
/// CoreGraphics 私有 API：切换虚拟桌面 + 查询当前桌面。用于跨桌面激活应用。
/// 符号不存在/调用失败时回退为普通 app.activate，行为不会比改动前差。
typealias CGSSpaceID = UInt32

private func cgsSymbol(_ name: String) -> UnsafeMutableRawPointer? {
    dlsym(dlopen(nil, RTLD_NOW), name)
}

private func cgsMainConnectionID() -> Int32 {
    typealias Fn = @convention(c) () -> Int32
    if let s = cgsSymbol("CGSMainConnectionID") { return unsafeBitCast(s, to: Fn.self)() }
    return 0
}

/// 当前活跃虚拟桌面的 id64（即 CGSSpaceID）
private func cgsCurrentSpaceID() -> CGSSpaceID? {
    typealias Fn = @convention(c) (Int32) -> UInt32
    guard let s = cgsSymbol("CGSGetActiveSpace") else { return nil }
    return unsafeBitCast(s, to: Fn.self)(cgsMainConnectionID())
}

private func cgsSwitchToSpace(_ spaceID: CGSSpaceID) -> Bool {
    typealias Fn = @convention(c) (Int32, CGSSpaceID, Int32, Int32) -> Int32
    guard let s = cgsSymbol("CGSSwitchToSpace") else { return false }
    return unsafeBitCast(s, to: Fn.self)(cgsMainConnectionID(), spaceID, 1, 0) == 0
}

/// 枚举所有虚拟桌面 id64（跨全部显示器的并集，Mission Control 顶部栏顺序）。
/// 数据源：~/Library/Preferences/com.apple.spaces.plist
/// → SpacesDisplayConfiguration → Management Data → Monitors[].Spaces[].id64
/// （macOS 26 实测：旧版 "Space Properties" 键已不存在，CGSGetSpaceID 符号也移除。）
func allSpaceIDs() -> [CGSSpaceID] {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Preferences/com.apple.spaces.plist")
    guard let dict = NSDictionary(contentsOf: url),
          let cfg = dict["SpacesDisplayConfiguration"] as? [String: Any],
          let mgmt = cfg["Management Data"] as? [String: Any],
          let monitors = mgmt["Monitors"] as? [[String: Any]] else { return [] }
    var ids: [CGSSpaceID] = []
    for mon in monitors {
        guard let spaces = mon["Spaces"] as? [[String: Any]] else { continue }
        for s in spaces {
            if let id = s["id64"] as? Int, !ids.contains(CGSSpaceID(id)) {
                ids.append(CGSSpaceID(id))
            }
        }
    }
    return ids
}

/// 应用当前是否有窗口显示在屏幕上（即位于当前桌面）
func appOnScreen(pid: pid_t) -> Bool {
    guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return true }
    return raw.contains { ($0[kCGWindowOwnerPID as String] as? Int) == Int(pid) }
}

/// 扫描所有虚拟桌面，返回该应用有窗口的桌面 id64；找不到返回 nil。
/// 没有任何公开 API 能直接查"窗口属于哪个桌面"，所以做实时探测：
/// 逐个桌面切过去，检查该应用窗口是否 on-screen，命中即停。
/// 只扫非当前桌面；当前桌面由调用方的 onScreen 检查覆盖。
/// 找到目标时系统停在该桌面（调用方直接激活）；找不到则切回原桌面。
func scanSpaceForApp(pid: pid_t) -> CGSSpaceID? {
    let connID = cgsMainConnectionID()
    guard connID != 0, cgsSymbol("CGSSwitchToSpace") != nil else { return nil }
    let current = cgsCurrentSpaceID()
    let candidates = allSpaceIDs().filter { $0 != current }
    guard !candidates.isEmpty else { return nil }

    var found: CGSSpaceID?
    for id in candidates {
        guard cgsSwitchToSpace(id) else { continue }
        Thread.sleep(forTimeInterval: 0.5)  // 等待桌面切换动画结束
        if appOnScreen(pid: pid) {
            found = id
            break
        }
    }
    if found == nil, let c = current {
        // 没找到：恢复原桌面
        let restored = cgsSwitchToSpace(c)
        log("space scan: target not found, restored to space \(c), result=\(restored)")
        Thread.sleep(forTimeInterval: 0.5)
    }
    return found
}

/// 跨虚拟桌面激活应用：当前桌面可见则直接激活；否则扫描所有桌面找到其窗口
/// 所在桌面，停在该桌面后激活。覆盖"所有桌面空间中已打开且有活动窗口的应用"。
/// 扫描涉及多次真实桌面切换（秒级），放到后台线程执行，不阻塞 UI。
func activateApp(_ app: AppInfo) {
    guard let running = NSRunningApplication(processIdentifier: app.pid) else { return }

    // 当前桌面可见 → 直接激活
    if appOnScreen(pid: app.pid) {
        running.activate(options: [.activateIgnoringOtherApps])
        return
    }

    DispatchQueue.global(qos: .userInitiated).async {
        guard let target = scanSpaceForApp(pid: app.pid) else {
            running.activate(options: [.activateIgnoringOtherApps])
            return
        }
        log("activating \(app.name): found on space \(target)")
        // 扫描结束时系统已停在该桌面，稍等动画收尾再激活
        Thread.sleep(forTimeInterval: 0.4)
        running.activate(options: [.activateIgnoringOtherApps])
    }
}

// MARK: - Global State
var currentApps: [AppInfo] = []
var currentIndex: Int = 0
var isVisible: Bool = false
var switchPanel: NSPanel?
var lastSelectedBundleID: String?
let cubeState = CubeStateModel()

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

class CubeStateModel: ObservableObject {
    @Published var index: Int = 0
    @Published var visible: Bool = false
    /// 面板等比缩放系数：小屏上窗口缩小，内容同步 scaleEffect，避免裁剪
    @Published var scale: CGFloat = 1.0
}

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("eSwitch 设置")
                    .font(.headline)
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            
            Divider()
            
            Form {
                Toggle("开机自启动", isOn: $settings.launchAtLogin)
                    .toggleStyle(.switch)
                    .padding(.vertical, 4)

                Picker("面板屏幕", selection: $settings.panelScreenMode) {
                    ForEach(PanelScreenMode.allCases, id: \.rawValue) { mode in
                        Text(mode.description).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Toggle("卡片窗口预览", isOn: $settings.windowPreview)
                    .toggleStyle(.switch)
                    .padding(.vertical, 4)
                if settings.windowPreview && !WindowPreviewProvider.shared.granted {
                    Button("打开「隐私与安全性 → 屏幕录制」授权") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                    }
                    .controlSize(.small)
                    .font(.caption)
                }
                Text(windowPreviewHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("快捷键")
                    .font(.subheadline.weight(.medium))
                HotkeyRecorderView(
                    label: "呼出/切换",
                    hotkey: $settings.showHotkey,
                    other: settings.prevHotkey
                )
                HotkeyRecorderView(
                    label: "反向切换",
                    hotkey: $settings.prevHotkey,
                    other: settings.showHotkey
                )
                HStack {
                    Text("选择应用")
                    Spacer()
                    Text(settings.showHotkey.releaseHint)
                        .foregroundColor(.secondary)
                }
                Text("点击右侧按钮后按下新的组合键即可重新录制，按 Esc 取消")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            HStack {
                Spacer()
                Text("v1.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .frame(width: 340, height: 395)
    }

    /// 窗口预览权限状态提示
    private var windowPreviewHint: String {
        if !settings.windowPreview { return "关闭时卡片显示 App 图标。" }
        if WindowPreviewProvider.shared.granted { return "卡片显示各应用最前窗口的实时内容。" }
        return "需要「屏幕录制」权限才能显示窗口内容，当前未授权（卡片暂用 App 图标）。"
    }
}

// MARK: - Hotkey Recorder
struct HotkeyRecorderView: View {
    let label: String
    @Binding var hotkey: Hotkey
    /// 另一个快捷键，用于检测冲突
    let other: Hotkey
    
    @State private var recording = false
    @State private var errorMessage: String?
    
    /// 全局「正在录制」的停止回调，保证同一时间只有一个录制器在工作
    private static var activeStop: (() -> Void)?
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Button(action: toggleRecording) {
                Text(buttonText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(errorMessage != nil ? .red : .primary)
                    .frame(minWidth: 110, alignment: .trailing)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(recording ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(recording ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .help(errorMessage ?? "点击后按下新的组合键")
        }
        .onDisappear(perform: stopRecording)
    }
    
    private var buttonText: String {
        if recording { return "正在监听，按下快捷键…" }
        if let errorMessage { return errorMessage }
        return hotkey.displayString
    }
    
    private func toggleRecording() {
        if recording {
            stopRecording()
        } else {
            // 若还有别的录制器在工作，先停掉它
            Self.activeStop?()
            errorMessage = nil
            recording = true
            log("Recorder[\(label)] start")
            // 录制期间暂停全局事件监听，避免旧快捷键在窗口内被触发
            setHotkeyTapEnabled(false)
            if let token = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { event in
                log("Recorder[\(self.label)] keyDown keyCode=\(event.keyCode) chars='\(event.characters ?? "?")' ignoringMods='\(event.charactersIgnoringModifiers ?? "?")' mask=\(Hotkey.mask(event.modifierFlags))")
                self.handleRecordedEvent(event)
                return nil  // 吞掉按键，避免触发系统/应用快捷键
            }) {
                Self.activeStop = {
                    log("Recorder[\(self.label)] stop")
                    NSEvent.removeMonitor(token)
                    self.recording = false
                    setHotkeyTapEnabled(true)
                }
            } else {
                log("Recorder[\(label)] FAILED to add monitor")
                errorMessage = "无法注册键盘监听"
                recording = false
                setHotkeyTapEnabled(true)
            }
        }
    }

    private func handleRecordedEvent(_ event: NSEvent) {
        let mask = Hotkey.mask(event.modifierFlags)
        // 单独按 Esc = 取消录制
        if Int(event.keyCode) == Hotkey.escKeyCode && mask == 0 {
            log("Recorder[\(label)] cancelled by Esc")
            errorMessage = nil
            stopRecording()
            return
        }
        guard mask != 0 else {
            log("Recorder[\(label)] rejected: no modifier")
            errorMessage = "需包含修饰键 (⌘/⌥/⌃/⇧)"
            stopRecording()
            return
        }
        let keyCode = Int(event.keyCode)
        if other.modifiers == mask && other.keyCode == keyCode {
            log("Recorder[\(label)] rejected: conflicts with other hotkey")
            errorMessage = "与另一快捷键冲突"
            stopRecording()
            return
        }
        let name = Hotkey.displayName(for: keyCode, characters: event.charactersIgnoringModifiers)
        hotkey = Hotkey(modifiers: mask, keyCode: keyCode, displayName: name)
        log("Recorder[\(label)] SAVED \(mask)+\(keyCode) '\(name)'")
        stopRecording()
    }
    
    private func stopRecording() {
        guard recording else { return }
        Self.activeStop?()
        Self.activeStop = nil
        recording = false
    }
}

// MARK: - App Card View
struct AppCardView: View {
    let app: AppInfo
    /// 窗口内容预览（nil 时降级为 App 图标）
    let preview: NSImage?
    /// 是否显示流光边框（环心卡片）。倒影复用同一视图，传 false。
    let showBorder: Bool

    /// 卡片内容：窗口预览优先，无预览（无权限/无窗口）降级为 App 图标。
    /// 应用名只显示在卡片上方（面板顶部标题），卡片内部不再重复。
    private var content: some View {
        Group {
            if let preview = preview {
                Image(nsImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Theme.cardWidth - 48, height: Theme.cardHeight - 48)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius * 0.4, style: .continuous))
            } else if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Theme.cardWidth - 48, height: Theme.cardHeight - 48)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 144))
                    .foregroundColor(.secondary)
            }
        }
    }

    var body: some View {
        let isFront = showBorder
        return content
            // 预览/图标与卡片边框保持 24pt 间距，最大化填满卡片
            .padding(24)
            .frame(width: Theme.cardWidth, height: Theme.cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .background(
            Group {
                if isFront {
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.20), .white.opacity(0.06), .white.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                } else {
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                }
            }
        )
        .overlay(
            Group {
                if isFront {
                    HighlightBorder(lineWidth: 6)
                } else {
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 3)
                }
            }
        )
        // shadow 只给正面卡片：倒影若再带 shadow，切换时 6 份高斯投影逐帧重算，
        // 是 GPU 峰值主因之一。倒影靠自身 alpha 淡出即可，视觉无损。
        .shadow(color: isFront ? Theme.accent.opacity(0.4) : .clear, radius: 24, x: 0, y: 0)
        .shadow(color: isFront ? Color.black.opacity(0.4) : .clear, radius: 18, x: 0, y: 18)
    }
}

struct IndexedCard: View {
    let index: Int
    let app: AppInfo
    let preview: NSImage?
    let currentIndex: Int
    let count: Int

    /// 归一化环偏移：-1..1 为可见邻位，0 为环心
    private var normalizedOffset: Int {
        var o = (index - currentIndex + count) % count
        if o > count / 2 { o -= count }
        return o
    }

    /// 环间距角：应用少时卡片大、角度大（Compiz Ring 感），应用多时收紧
    private var ringPitch: Double {
        switch count {
        case 1: return 0
        case 2: return 55
        case 3: return 42
        case 4: return 36
        default: return 30
        }
    }

    /// 相邻卡片中心距（与 240pt 卡片宽对应，环上略有重叠）
    private let slotWidth: CGFloat = Theme.slotWidth
    // 侧卡下沉量
    private let sideDrop: CGFloat = 30   // 10 × 3

    /// 中间卡片放大系数：放大后卡片栈底边与两侧卡片底边对齐
    private let frontScale: CGFloat = 1.16

    var body: some View {
        let off = normalizedOffset
        let angle = Double(off) * ringPitch
        let visible = abs(off) <= 1
        return cardStack(front: off == 0)
            .scaleEffect(off == 0 ? frontScale : 1.0)
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .offset(x: CGFloat(off) * slotWidth, y: CGFloat(abs(off)) * sideDrop)
            .opacity(visible ? 1.0 : 0.0)
            .zIndex(off == 0 ? 10.0 : 5.0 - Double(abs(off)))
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: currentIndex)
    }

    /// 卡片 + 下方地面倒影（随卡片一起旋转，模拟 Compiz Ring 的地板反射）
    private func cardStack(front: Bool) -> some View {
        VStack(spacing: 18) {
            AppCardView(app: app, preview: preview, showBorder: front)
            // 倒影：垂直翻转 + 上亮下暗渐变淡出 + 轻模糊
            AppCardView(app: app, preview: preview, showBorder: false)
                .scaleEffect(y: -1)
                .frame(height: 132, alignment: .top)
                .clipped()
                .mask(
                    LinearGradient(
                        colors: [Color.white.opacity(0.85), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .blur(radius: 3)
                .opacity(0.6)
                .allowsHitTesting(false)
        }
    }
}

/// 底部进度指示点
struct DotsIndicator: View {
    let count: Int
    let currentIndex: Int

    var body: some View {
        HStack(spacing: 18) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == currentIndex ? Theme.accent : Color.white.opacity(0.38))
                    .frame(width: i == currentIndex ? 42 : 15, height: 15)
                    .animation(.spring(response: 0.3, dampingFraction: 0.9), value: currentIndex)
            }
        }
    }
}

struct SwitcherView: View {
    @ObservedObject var state: CubeStateModel
    @ObservedObject private var previewProvider = WindowPreviewProvider.shared

    var body: some View {
        GlassContainer {
            VStack(spacing: 42) {
                // 顶部：当前应用名
                Text(currentAppName)
                    .font(.system(size: 51, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(height: 66)

                // 中间：卡片轮播
                if currentApps.isEmpty {
                    VStack {
                        Image(systemName: "app.fill")
                            .font(.system(size: 120))
                            .foregroundColor(Theme.dimmerText)
                        Text("没有可切换的应用")
                            .font(.system(size: 36))
                            .foregroundColor(Theme.dimmerText)
                            .padding(.top, 24)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.cardAreaHeight)
                } else {
                    GeometryReader { geo in
                        ZStack {
                            ForEach(currentApps.indices, id: \.self) { i in
                                IndexedCard(
                                    index: i,
                                    app: currentApps[i],
                                    preview: previewProvider.previews[currentApps[i].id],
                                    currentIndex: state.index,
                                    count: currentApps.count
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(height: Theme.cardAreaHeight)

                    // 底部：进度点
                    DotsIndicator(count: currentApps.count, currentIndex: state.index)
                        .padding(.bottom, 6)
                }
            }
            .padding(.horizontal, 96)
            .padding(.top, 60)
            .frame(width: Theme.panelWidth, height: Theme.panelHeight)
        }
        // 呼出入场 / 收起退场动画（由模型 visible 驱动，每次呼出都会重播）
        .scaleEffect(state.visible ? state.scale : 0.94 * state.scale)
        .opacity(state.visible ? 1.0 : 0.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: state.visible)
    }

    private var currentAppName: String {
        guard !currentApps.isEmpty, state.index < currentApps.count else { return " " }
        return currentApps[state.index].name
    }
}

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
        panel.hasShadow = false  // 阴影由 SwiftUI 内容自身绘制，跟随圆角
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
    // 面板可能大于屏幕：等比缩放到屏幕 95% 内，内容同步 scaleEffect 避免裁剪
    let s = min(1.0, sf.width * 0.95 / Theme.panelWidth, sf.height * 0.95 / Theme.panelHeight)
    cubeState.scale = s
    let sw = Theme.panelWidth * s
    let sh = Theme.panelHeight * s
    switchPanel?.setFrame(NSRect(x: sf.midX - sw / 2, y: sf.midY - sh / 2, width: sw, height: sh), display: true)
    
    // 窗口预览：每次呼出异步刷新一次（未授权/关闭时自动跳过，卡片保持 App 图标）
    if SettingsManager.shared.windowPreview {
        WindowPreviewProvider.shared.refresh(apps: currentApps)
    }
    
    switchPanel?.orderFront(nil)
}

func hideSwitcher(activate: Bool = true) {
    log("hideSwitcher(activate: \(activate))")
    isVisible = false
    cubeState.visible = false
    switchPanel?.orderOut(nil)
    
    if activate, !currentApps.isEmpty && currentIndex < currentApps.count {
        let target = currentApps[currentIndex]
        lastSelectedBundleID = target.id
        activateApp(target)
    }
}

func rotateNext() {
    guard !currentApps.isEmpty else { return }
    currentIndex = (currentIndex + 1) % currentApps.count
    cubeState.index = currentIndex
    log("rotate -> \(currentIndex): \(currentApps[currentIndex].name)")
}

func rotatePrev() {
    guard !currentApps.isEmpty else { return }
    currentIndex = (currentIndex - 1 + currentApps.count) % currentApps.count
    cubeState.index = currentIndex
    log("rotate <- \(currentIndex): \(currentApps[currentIndex].name)")
}

// MARK: - Keyboard
var globalEventTap: CFMachPort?

/// 录制快捷键期间暂停/恢复全局事件监听
func setHotkeyTapEnabled(_ enabled: Bool) {
    guard let tap = globalEventTap else { return }
    CGEvent.tapEnable(tap: tap, enable: enabled)
}

func setupKeyboard() {
    log("Setting up keyboard...")
    
    let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                            (1 << CGEventType.flagsChanged.rawValue)
    
    let tap = CGEvent.tapCreate(
        tap: .cghidEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
            // 系统因超时/用户输入而禁用 tap 时自动恢复
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = globalEventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }
            
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let mods = Hotkey.mask(event.flags)
            
            if type == .flagsChanged {
                // 切换器显示时：呼出快捷键的全部修饰键被松开 = 确认选择
                if isVisible {
                    let showMods = SettingsManager.shared.showHotkey.modifiers
                    if (mods & showMods) != showMods {
                        DispatchQueue.main.async {
                            if isVisible { hideSwitcher() }
                        }
                    }
                }
            } else if type == .keyDown {
                let settings = SettingsManager.shared
                let show = settings.showHotkey
                let prev = settings.prevHotkey
                
                if mods != 0 || isVisible {
                    log("Tap keyDown keyCode=\(keyCode) mods=\(mods) show=\(show.modifiers)+\(show.keyCode) prev=\(prev.modifiers)+\(prev.keyCode)")
                }
                
                if mods == show.modifiers && keyCode == show.keyCode {
                    // 呼出/切换：未显示则呼出，显示中则下一个
                    DispatchQueue.main.async {
                        if isVisible { rotateNext() } else { showSwitcher() }
                    }
                    return nil
                } else if isVisible && mods == prev.modifiers && keyCode == prev.keyCode {
                    // 反向切换：上一个
                    DispatchQueue.main.async { rotatePrev() }
                    return nil
                } else if isVisible && mods == 0 && keyCode == Hotkey.escKeyCode {
                    // 切换器显示时单独按 Esc = 取消（不激活应用）
                    DispatchQueue.main.async {
                        if isVisible { hideSwitcher(activate: false) }
                    }
                    return nil
                }
            }
            
            return Unmanaged.passUnretained(event)
        },
        userInfo: nil
    )
    
    if let tap = tap {
        globalEventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        log("CGEvent tap OK")
    } else {
        log("CGEvent tap FAILED")
    }
}

// MARK: - Settings Window
var settingsWindow: NSWindow?

func showSettings() {
    // 静默刷新屏幕录制授权状态（用户可能刚在系统设置里授权）
    WindowPreviewProvider.shared.preflight()
    if let existing = settingsWindow, existing.isVisible {
        existing.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        return
    }
    
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 340, height: 395),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    window.title = "eSwitch 设置"
    window.contentView = NSHostingView(rootView: SettingsView())
    window.isReleasedWhenClosed = false
    
    if let screen = NSScreen.main {
        let sf = screen.visibleFrame
        let wf = window.frame
        window.setFrameOrigin(NSPoint(x: sf.midX - wf.width / 2, y: sf.midY - wf.height / 2))
    }
    
    window.makeKeyAndOrderFront(nil)
    NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
    settingsWindow = window
}

// MARK: - Status Bar
var statusItem: NSStatusItem?

/// 托盘图标：代码绘制的「中间卡片 + 双向箭头」模板图标，与新 App 图标同构，自动适配深浅菜单栏。
/// lockFocus 按屏幕 backing scale 渲染（Retina 自动 2x），矢量绘制 18pt 下锐利不糊。
func statusBarIconImage() -> NSImage {
    let s: CGFloat = 18
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    NSColor.white.setFill()

    // 中间圆角卡片（实心）
    let card = NSBezierPath(
        roundedRect: NSRect(x: 5.0, y: 5.0, width: 8.0, height: 8.0),
        xRadius: 2.0, yRadius: 2.0
    )
    card.fill()

    // 左侧左向箭头（杆在卡片背后，只露出头部）
    let leftArrow = NSBezierPath()
    leftArrow.move(to: NSPoint(x: 0.8, y: 9.0))          // 箭尖
    leftArrow.line(to: NSPoint(x: 3.6, y: 11.0))
    leftArrow.line(to: NSPoint(x: 3.6, y: 10.0))
    leftArrow.line(to: NSPoint(x: 5.0, y: 10.0))
    leftArrow.line(to: NSPoint(x: 5.0, y: 8.0))
    leftArrow.line(to: NSPoint(x: 3.6, y: 8.0))
    leftArrow.line(to: NSPoint(x: 3.6, y: 7.0))
    leftArrow.close()
    leftArrow.fill()

    // 右侧右向箭头（镜像）
    let rightArrow = NSBezierPath()
    rightArrow.move(to: NSPoint(x: 17.2, y: 9.0))        // 箭尖
    rightArrow.line(to: NSPoint(x: 14.4, y: 11.0))
    rightArrow.line(to: NSPoint(x: 14.4, y: 10.0))
    rightArrow.line(to: NSPoint(x: 13.0, y: 10.0))
    rightArrow.line(to: NSPoint(x: 13.0, y: 8.0))
    rightArrow.line(to: NSPoint(x: 14.4, y: 8.0))
    rightArrow.line(to: NSPoint(x: 14.4, y: 7.0))
    rightArrow.close()
    rightArrow.fill()

    img.unlockFocus()
    img.isTemplate = true  // 单色模板：深色菜单栏显示白色，浅色菜单栏显示黑色
    return img
}

func setupStatusBar() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem?.button?.image = statusBarIconImage()
    
    let menu = NSMenu()
    
    let titleItem = NSMenuItem(title: "eSwitch v1.0", action: nil, keyEquivalent: "")
    titleItem.isEnabled = false
    menu.addItem(titleItem)
    menu.addItem(NSMenuItem.separator())
    
    let settingsItem = NSMenuItem(title: "设置...", action: #selector(AppDelegate.showSettingsAction), keyEquivalent: ",")
    settingsItem.target = AppDelegate.shared
    menu.addItem(settingsItem)
    
    let accItem = NSMenuItem(title: "辅助功能权限", action: #selector(AppDelegate.checkAccessibility), keyEquivalent: "")
    accItem.target = AppDelegate.shared
    menu.addItem(accItem)
    
    menu.addItem(NSMenuItem.separator())
    
    let quitItem = NSMenuItem(title: "退出", action: #selector(AppDelegate.quit), keyEquivalent: "q")
    quitItem.target = AppDelegate.shared
    menu.addItem(quitItem)
    
    statusItem?.menu = menu
}

// MARK: - AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        log("Launched")
        setupStatusBar()
        setupKeyboard()
        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
        }
        // 窗口预览：启动时请求屏幕录制权限（未授权弹一次系统授权框，之后不再打扰）
        WindowPreviewProvider.shared.requestPermission()
    }
    
    @objc func showSettingsAction() {
        showSettings()
    }
    
    @objc func checkAccessibility() {
        let hk = SettingsManager.shared.showHotkey
        let alert = NSAlert()
        if AXIsProcessTrusted() {
            alert.messageText = "辅助功能权限已启用"
            alert.informativeText = "使用 \(hk.displayString) 呼出切换器。\n按住 \(hk.modifierString)，每按一次按键切换到下一个应用。\n\(hk.releaseHint)激活当前应用。\n\n可在「设置...」中自定义快捷键。"
            alert.alertStyle = .informational
        } else {
            alert.messageText = "需要辅助功能权限"
            alert.informativeText = "请在系统设置中启用 eSwitch 的辅助功能权限。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "打开系统设置")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            return
        }
        alert.runModal()
    }
    
    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Main
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.delegate = AppDelegate.shared
app.run()
