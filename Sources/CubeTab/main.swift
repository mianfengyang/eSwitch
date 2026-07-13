import AppKit
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

// MARK: - Settings Manager
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            setLaunchAtLogin(launchAtLogin)
        }
    }
    
    private init() {
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
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
            }
            .padding()
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("快捷键")
                    .font(.subheadline.weight(.medium))
                HStack {
                    Text("呼出/切换")
                    Spacer()
                    KeyboardShortcutLabel(keys: ["⌘", "esc"])
                }
                HStack {
                    Text("选择应用")
                    Spacer()
                    Text("松开 ⌘ 键")
                        .foregroundColor(.secondary)
                }
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
        .frame(width: 340, height: 320)
    }
}

struct KeyboardShortcutLabel: View {
    let keys: [String]
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                    )
            }
        }
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
        .overlay(
            Group {
                if isFront {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.85), .white.opacity(0.35), .white.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                    Circle()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 20, height: 20)
                        .offset(x: -35, y: -45)
                        .blur(radius: 4)
                }
            }
        )
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
        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: sf.midX - 240, y: sf.midY - 150))
        }
        switchPanel = panel
    }
    
    switchPanel?.orderFront(nil)
}

func hideSwitcher() {
    log("hideSwitcher")
    isVisible = false
    switchPanel?.orderOut(nil)
    
    if !currentApps.isEmpty && currentIndex < currentApps.count {
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

// MARK: - Keyboard
var isCmdDown = false

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
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            let cmd = flags.contains(.maskCommand)
            
            if type == .flagsChanged {
                if cmd && !isCmdDown {
                    isCmdDown = true
                } else if !cmd && isCmdDown {
                    isCmdDown = false
                    DispatchQueue.main.async {
                        if isVisible { hideSwitcher() }
                    }
                }
            } else if type == .keyDown && isCmdDown && keyCode == 53 {
                DispatchQueue.main.async {
                    if isVisible { rotateNext() } else { showSwitcher() }
                }
                return nil
            }
            
            return Unmanaged.passUnretained(event)
        },
        userInfo: nil
    )
    
    if let tap = tap {
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
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
        contentRect: NSRect(x: 0, y: 0, width: 340, height: 320),
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
        let alert = NSAlert()
        if AXIsProcessTrusted() {
            alert.messageText = "辅助功能权限已启用"
            alert.informativeText = "使用 Command + esc 呼出切换器。\n按住 ⌘ 不放，每按一次 esc 切换下一个应用。\n松开 ⌘ 激活当前应用。"
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
