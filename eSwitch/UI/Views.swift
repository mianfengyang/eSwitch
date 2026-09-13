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
                Text("v1.2")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .frame(width: 340, height: 395)
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
    /// 是否显示流光边框（环心卡片）。倒影复用同一视图，传 false。
    let showBorder: Bool
    /// 是否在卡片顶部叠加同字母候选角标（字母定位时调用方判定后传入）
    var showCandidateBadge: Bool = false

    /// 首字母展示色（#EB6217）
    static let initialColor = Color(red: 0xEB / 255, green: 0x62 / 255, blue: 0x17 / 255)

    /// 卡片内容：App 图标 + 顶部应用名首字母。
    /// 应用全名只显示在卡片上方（面板顶部标题），卡片内部只留首字母。
    private var content: some View {
        ZStack(alignment: .top) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Theme.cardWidth - 24, height: Theme.cardHeight - 24)
                    .padding(.top, 18)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.secondary)
            }
            Text(app.englishName.switcherInitial)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(Self.initialColor)
                .opacity(0.95)
                .padding(.top, 2)
        }
    }

    var body: some View {
        let isFront = showBorder
        return content
            // 预览/图标与卡片边框保持 12pt 间距，最大化填满卡片
            .padding(12)
            .frame(width: Theme.cardWidth, height: Theme.cardHeight)
            .overlay(alignment: .top) {
                if showCandidateBadge {
                    // 字母定位候选角标：同首字母应用保留原环位并高亮提示
                    // （环心卡片不叠加：其内容区首字母已足够醒目）
                    Text(app.englishName.switcherInitial)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(AppCardView.initialColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.white.opacity(0.22)))
                        .padding(.top, 6)
                        .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(isFront ? Color.white.opacity(0.18) : Color.white.opacity(0.10))
        )
        .overlay(
            Group {
                if isFront {
                    HighlightBorder(lineWidth: 3)
                } else {
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 1.5)
                }
            }
        )
        // 移除阴影：GPU 主要消耗源。系统窗口阴影（panel.hasShadow）已提供足够深度感
    }
}

struct IndexedCard: View {
    let index: Int
    let app: AppInfo
    let currentIndex: Int
    let count: Int
    /// 字母定位：同首字母候选下标列表（非定位模式传 []）
    var candidates: [Int] = []
    /// 字母定位跳转目标（环心内容来源，非定位模式传 nil）
    var jumpIndex: Int? = nil

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
    private let sideDrop: CGFloat = 15   // 7.5 × 2

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
            // 字母定位：候选卡片保留原环位、仅提亮；非候选非环心卡片压暗
            .opacity(visible ? (jumpIndex == nil || off == 0 || candidates.contains(index) ? 1.0 : 0.35) : 0.0)
            .zIndex(off == 0 ? 10.0 : 5.0 - Double(abs(off)))
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: currentIndex)
    }

    /// 卡片 + 下方地面倒影（随卡片一起旋转，模拟 Compiz Ring 的地板反射）
    private func cardStack(front: Bool) -> some View {
        let isJump = jumpIndex != nil
        let cardIdx = front ? (jumpIndex ?? index) : index
        let isCandidate = isJump && candidates.contains(cardIdx)
        return VStack(spacing: 9) {
            AppCardView(app: app, showBorder: front, showCandidateBadge: isCandidate)
            // 倒影：垂直翻转 + 上亮下暗渐变淡出 + 轻模糊（角标随主卡镜像）
            AppCardView(app: app, showBorder: false, showCandidateBadge: isCandidate)
                .scaleEffect(y: -1)
                .frame(height: 66, alignment: .top)
                .clipped()
                .mask(
                    LinearGradient(
                        colors: [Color.white.opacity(0.85), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .opacity(0.5)
                .allowsHitTesting(false)
        }
    }
}

/// 底部进度指示点
struct DotsIndicator: View {
    let count: Int
    let currentIndex: Int

    var body: some View {
        HStack(spacing: 9) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == currentIndex ? Theme.accent : Color.white.opacity(0.38))
                    .frame(width: i == currentIndex ? 21 : 7.5, height: 7.5)
                    .animation(.spring(response: 0.3, dampingFraction: 0.9), value: currentIndex)
            }
        }
    }
}

struct SwitcherView: View {
    @ObservedObject var state: CubeStateModel

    /// 当前环心卡片下标：字母定位跳转时以 jumpIndex 为准，否则跟随 index。
    private var frontIndex: Int {
        state.jumpIndex ?? state.index
    }

    var body: some View {
        GlassContainer {
            VStack(spacing: 21) {
                // 顶部：当前应用名（字母定位后显示跳转目标）
                Text(frontAppName)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(height: 33)

                // 中间：卡片轮播
                if currentApps.isEmpty {
                    VStack {
                        Image(systemName: "app.fill")
                            .font(.system(size: 60))
                            .foregroundColor(Theme.dimmerText)
                        Text("没有可切换的应用")
                            .font(.system(size: 18))
                            .foregroundColor(Theme.dimmerText)
                            .padding(.top, 12)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.cardAreaHeight)
                } else {
                    GeometryReader { geo in
                        ZStack {
                            ForEach(currentApps.indices, id: \.self) { i in
                                let cardIdx = i == state.index ? frontIndex : i
                                IndexedCard(
                                    index: i,
                                    app: currentApps[cardIdx],
                                    currentIndex: state.index,
                                    count: currentApps.count,
                                    candidates: state.candidates,
                                    jumpIndex: state.jumpIndex
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(height: Theme.cardAreaHeight)

                    // 底部：进度点（字母定位时指示环心）
                    DotsIndicator(count: currentApps.count, currentIndex: frontIndex)
                        .padding(.bottom, 3)
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 30)
            .frame(width: Theme.panelWidth, height: Theme.panelHeight)
        }
        // 呼出入场 / 收起退场动画（由模型 visible 驱动，每次呼出都会重播）
        .scaleEffect(state.visible ? state.scale : 0.94 * state.scale)
        .opacity(state.visible ? 1.0 : 0.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: state.visible)
    }

    private var frontAppName: String {
        guard frontIndex < currentApps.count else { return " " }
        return currentApps[frontIndex].name
    }
}
