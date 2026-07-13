import AppKit
import SwiftUI

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

struct AppInfo {
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
        return AppInfo(name: name, icon: app.icon, pid: app.processIdentifier)
    }
}

var currentApps: [AppInfo] = []
var currentIndex: Int = 0
var isVisible: Bool = false
var switchPanel: NSPanel?
let cubeState = CubeStateModel()

class CubeStateModel: ObservableObject {
    @Published var index: Int = 0
}

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
                    .shadow(color: .black.opacity(0.2), radius: 4)
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
        .frame(width: 120, height: 140)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(isFront ? 0.25 : 0.08), radius: isFront ? 12 : 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isFront ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 2)
        )
        .scaleEffect(isFront ? 1.0 : 0.78)
        .opacity(isFront ? 1.0 : 0.55)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFront)
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
            .offset(x: CGFloat(off) * width * 0.55)
            .scaleEffect(off == 0 ? 1.0 : abs(off) == 1 ? 0.8 : 0.6)
            .opacity(off == 0 ? 1.0 : abs(off) == 1 ? 0.6 : 0.2)
            .zIndex(index == currentIndex ? 10.0 : 5.0 - Double(abs(off)))
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
                .frame(width: 500, height: 400)
            } else {
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
                .frame(width: 500, height: 400)
            }
        }
    }
}

class SwitchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

func showSwitcher() {
    log("showSwitcher")
    currentApps = getApps()
    guard !currentApps.isEmpty else { log("no apps"); return }
    cubeState.index = 0
    currentIndex = 0
    isVisible = true
    
    if switchPanel == nil {
        let panel = SwitchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
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
            panel.setFrameOrigin(NSPoint(x: sf.midX - 250, y: sf.midY - 200))
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

var isCmdDown = false
var gMonitor: Any?
var lMonitor: Any?

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

func handleKey(_ event: NSEvent) {
    let cmd = event.modifierFlags.contains(.command)
    log("Key event: type=\(event.type.rawValue) keyCode=\(event.keyCode) cmd=\(cmd)")
    
    switch event.type {
    case .flagsChanged:
        if cmd && !isCmdDown {
            isCmdDown = true
        } else if !cmd && isCmdDown {
            isCmdDown = false
            DispatchQueue.main.async {
                if isVisible { hideSwitcher() }
            }
        }
    case .keyDown:
        if isCmdDown && event.keyCode == 53 {
            log("ESC+CMD!")
            DispatchQueue.main.async {
                if isVisible { rotateNext() } else { showSwitcher() }
            }
        }
    default:
        break
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        log("Launched")
        setupKeyboard()
        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.delegate = AppDelegate()
app.run()
