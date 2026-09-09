import AppKit
import SwiftUI

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
