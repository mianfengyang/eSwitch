import AppKit
import SwiftUI

// MARK: - Theme
/// 中性灰玻璃主题。卡片描边/选中光环使用系统强调色（跟随用户系统主题）。
/// v1.4: 面板整体 3 倍尺寸（适配 26 系统大屏），形状/比例不变。
/// v1.5: 面板与卡片整体缩小到 3 倍的一半（即 1.5 倍基准）。
enum Theme {
    static let accent = Color.accentColor
    static let panelRadius: CGFloat = 36      // 24 × 1.5
    static let cardRadius: CGFloat = 24       // 16 × 1.5
    static let dimText = Color.white.opacity(0.55)
    static let dimmerText = Color.white.opacity(0.4)
    // 面板固定尺寸
    static let panelWidth: CGFloat = 630     // 420 × 1.5
    static let panelHeight: CGFloat = 405     // 270 × 1.5
    static let cardWidth: CGFloat = 136       // 卡片减半
    static let cardHeight: CGFloat = 146      // 卡片减半
    static let slotWidth: CGFloat = 165       // 环间距减半
    static let cardAreaHeight: CGFloat = 239  // 卡片区高度减半
}

// MARK: - Glass Container
/// 圆角玻璃面板背景。
/// 说明：这里的背景完全用 SwiftUI 圆角路径绘制，不引入 NSVisualEffectView。
/// 窗口 backdrop 层的 behindWindow 材质始终以整个窗口矩形渲染，圆角外必然露出
/// 可以直角的灰底（view 的 clipShape / maskImage 都裁不掉窗口级 backdrop）。
/// 为保证「圆角外 100% 透明」，背景改成纯 SwiftUI 半透明圆角层，透明由透明窗口保证，
/// 圆角由路径本身精确生成——这是唯一能彻底消除直角灰底的做法。
struct GlassContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.16, green: 0.17, blue: 0.20).opacity(0.94),
                                Color(red: 0.10, green: 0.11, blue: 0.13).opacity(0.98)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.12), .clear, .black.opacity(0.18)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                    )
            )
            // 阴影交给系统窗口阴影（panel.hasShadow = true，见 Panel.swift），
            // 系统会贴合内容不透明轮廓生成圆角阴影，避免 SwiftUI 自绘阴影按
            // 视图矩形边界投影而在四角露出直角阴影。
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
