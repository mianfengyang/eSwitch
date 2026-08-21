import AppKit
import CoreGraphics
import SwiftUI
import ServiceManagement

func log(_ msg: String) {
    let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    let line = "[\(ts)] \(msg)\n"
    let path = "/tmp/cubetab_debug.log"
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
    
    private init() {
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
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

func getApps() -> [AppInfo] {
    NSWorkspace.shared.runningApplications.filter {
        $0.activationPolicy == .regular &&
        $0.bundleIdentifier != Bundle.main.bundleIdentifier &&
        $0.bundleIdentifier != "com.apple.finder"
    }.compactMap { app in
        guard let name = app.localizedName else { return nil }
        return AppInfo(id: app.bundleIdentifier ?? UUID().uuidString, name: name, icon: app.icon, pid: app.processIdentifier)
    }
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
}

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CubeTab 设置")
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
        .frame(width: 340, height: 359)
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
    let isFront: Bool
    
    var body: some View {
        VStack(spacing: 10) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 72)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.secondary)
            }
            Text(app.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .frame(width: 120, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .background(
            Group {
                if isFront {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.22), .white.opacity(0.08), .white.opacity(0.14)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                } else {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.12))
                }
            }
        )
        .overlay {
            if isFront {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white, lineWidth: 3)
            }
        }
        .shadow(color: isFront ? .white.opacity(0.4) : .clear, radius: 8, x: 0, y: 0)
        .shadow(color: isFront ? .black.opacity(0.25) : .clear, radius: 6, x: 0, y: 3)
    }
}

struct IndexedCard: View {
    let index: Int
    let app: AppInfo
    let currentIndex: Int
    let count: Int
    let width: CGFloat
    
    var body: some View {
        let off = normalizedOffset
        return AppCardView(app: app, isFront: index == currentIndex)
            .frame(width: width)
            .offset(x: CGFloat(off) * width * 0.45)
            .scaleEffect(off == 0 ? 1.0 : 0.78)
            .opacity(off == 0 ? 1.0 : abs(off) == 1 ? 0.75 : 0.0)
            .zIndex(index == currentIndex ? 10.0 : 5.0 - Double(abs(off)))
            .animation(.easeInOut(duration: 0.25), value: currentIndex)
    }
    
    private var normalizedOffset: Int {
        var o = (index - currentIndex + count) % count
        if o > count / 2 { o -= count }
        return o
    }
}

struct SwitcherView: View {
    @ObservedObject var state: CubeStateModel
    
    var body: some View {
        ZStack {
            if currentApps.isEmpty {
                VStack {
                    Image(systemName: "app.fill").font(.system(size: 40)).foregroundColor(.secondary)
                    Text("没有可切换的应用").foregroundColor(.secondary).padding(.top, 8)
                }
                .frame(width: 480, height: 300)            } else {
                GeometryReader { geo in
                    ZStack {
                        ForEach(currentApps.indices, id: \.self) { i in
                            IndexedCard(
                                index: i,
                                app: currentApps[i],
                                currentIndex: state.index,
                                count: currentApps.count,
                                width: geo.size.width
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: 480, height: 300)
            }
        }
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
    
    if switchPanel == nil {
        let panel = SwitchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentView = NSHostingView(rootView: SwitcherView(state: cubeState))
        switchPanel = panel
    }

    // Always reposition when showing (settings may have changed)
    let screen = getTargetScreen()
    let sf = screen.visibleFrame
    switchPanel?.setFrameOrigin(NSPoint(x: sf.midX - 240, y: sf.midY - 150))
    
    switchPanel?.orderFront(nil)
}

func hideSwitcher(activate: Bool = true) {
    log("hideSwitcher(activate: \(activate))")
    isVisible = false
    switchPanel?.orderOut(nil)
    
    if activate, !currentApps.isEmpty && currentIndex < currentApps.count {
        let target = currentApps[currentIndex]
        lastSelectedBundleID = target.id
        if let app = NSRunningApplication(processIdentifier: target.pid) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
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
    if let existing = settingsWindow, existing.isVisible {
        existing.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        return
    }
    
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 340, height: 359),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    window.title = "CubeTab 设置"
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

func setupStatusBar() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem?.button?.image = NSImage(systemSymbolName: "cube.fill", accessibilityDescription: "CubeTab")
    
    let menu = NSMenu()
    
    let titleItem = NSMenuItem(title: "CubeTab v1.0", action: nil, keyEquivalent: "")
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
            alert.informativeText = "请在系统设置中启用 CubeTab 的辅助功能权限。"
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
