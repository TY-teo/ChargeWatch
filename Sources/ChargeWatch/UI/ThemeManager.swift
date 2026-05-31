import SwiftUI
import AppKit

enum AppTheme: String, CaseIterable, Identifiable {
    case classic
    case vibrancy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "经典"
        case .vibrancy: return "玻璃"
        }
    }

    var description: String {
        switch self {
        case .classic: return "不透明面板，跟随系统深浅模式"
        case .vibrancy: return "磨砂玻璃质感，桌面隐约可见"
        }
    }
}

extension View {
    /// 面板背景。classic 用不透明窗口底；vibrancy 用系统原生 popover 材质，
    /// 完全跟随系统深浅模式（不再强制浅色），与控制中心一致。
    @ViewBuilder
    func panelBackground(theme: AppTheme) -> some View {
        switch theme {
        case .classic:
            background(AppColor.bgPrimary)
        case .vibrancy:
            background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        }
    }

    /// 独立窗口背景。classic 不透明；vibrancy 用窗下材质透出桌面，跟随系统外观。
    @ViewBuilder
    func windowBackground(theme: AppTheme) -> some View {
        switch theme {
        case .classic:
            background(AppColor.bgPrimary)
        case .vibrancy:
            background(VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow))
        }
    }

    /// 主题感知卡片表面。
    /// classic：不透明控件底 + hairline，保持清晰层级。
    /// vibrancy：不再叠第二层材质（避免 glass-on-glass），而是用 Color.primary.opacity
    /// 派生的极淡色块抬升卡片，深浅模式自动反相，配 hairline 勾边。
    @ViewBuilder
    func cardSurface(theme: AppTheme, radius: CGFloat = AppRadius.m) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch theme {
        case .classic:
            self
                .background(shape.fill(AppColor.bgSecondary))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.05), lineWidth: 1))
        case .vibrancy:
            self
                .background(shape.fill(Color.primary.opacity(0.05)))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }

    /// 兼容保留：历史上用于强制玻璃主题浅色配色，现已废弃为 no-op，
    /// 外观一律跟随系统。保留签名以免调用点破裂。
    @available(*, deprecated, message: "外观跟随系统，无需强制配色；此修饰符已为 no-op")
    @ViewBuilder
    func glassAppearance(_ theme: AppTheme) -> some View {
        self
    }
}

@MainActor
enum ThemeWindowConfigurator {
    /// 让窗口允许 SwiftUI 控制背景，并支持 vibrancy 透传桌面。
    /// 标题栏保留默认 chrome（含标题文本），最大化兼容 v0.1.0 视觉。
    static func prepareForThemeable(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        // 保留系统标题栏（可见、可拖拽）；玻璃感由内容区材质提供，不再让标题栏透明。
    }
}
