import SwiftUI
import AppKit

/// 原生磨砂材质桥接：直接复用 NSVisualEffectView，外观完全跟随系统深浅模式。
/// 不再强制 Aqua（强制浅色曾导致深色模式下文字与叠底失效），让玻璃在 light/dark 都自然。
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    var emphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        apply(to: view)
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = blendingMode
        view.isEmphasized = emphasized
        // 不设置 appearance：继承窗口/系统外观，light 与 dark 一致地正确渲染。
    }
}
