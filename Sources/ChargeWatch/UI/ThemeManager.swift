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
    @ViewBuilder
    func panelBackground(theme: AppTheme) -> some View {
        switch theme {
        case .classic:
            background(AppColor.bgPrimary)
        case .vibrancy:
            background(VisualEffectView(material: .popover, blendingMode: .behindWindow, forceAqua: true))
                .glassAppearance(theme)
        }
    }

    @ViewBuilder
    func windowBackground(theme: AppTheme) -> some View {
        switch theme {
        case .classic:
            background(AppColor.bgPrimary)
        case .vibrancy:
            // 去掉旧版厚重蓝色水洗，换更干净的窗下材质并强制浅色，玻璃更亮更原生。
            background(VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow, forceAqua: true))
                .glassAppearance(theme)
        }
    }

    /// 主题感知卡片表面：classic 用不透明控件底，vibrancy 用半透明磨砂瓦片，
    /// 二者均带 hairline 描边，保持卡片层级并与磨砂面板协调（替代直接铺 bgSecondary）。
    @ViewBuilder
    func cardSurface(theme: AppTheme, radius: CGFloat = AppRadius.m) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch theme {
        case .classic:
            self
                .background(shape.fill(AppColor.bgSecondary))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.05), lineWidth: 1))
        case .vibrancy:
            // 用更实一些的材质 + 一层浅色叠底，提升瓦片亮度与可读性。
            self
                .background(shape.fill(Color.white.opacity(0.5)))
                .background(shape.fill(.regularMaterial))
                .overlay(shape.strokeBorder(Color.black.opacity(0.06), lineWidth: 1))
        }
    }

    /// 玻璃主题强制浅色配色：语义色回到经典浅色变体，文字保持深色可读，避免暗模式霓虹色。
    @ViewBuilder
    func glassAppearance(_ theme: AppTheme) -> some View {
        switch theme {
        case .classic:
            self
        case .vibrancy:
            environment(\.colorScheme, .light)
        }
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
