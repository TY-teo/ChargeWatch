import SwiftUI
import AppKit

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    var emphasized: Bool = false
    /// 玻璃主题强制浅色外观：让磨砂材质更亮、语义色回到经典浅色配色，贴近原生控制中心。
    var forceAqua: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        apply(to: v)
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to v: NSVisualEffectView) {
        v.material = material
        v.blendingMode = blendingMode
        v.isEmphasized = emphasized
        v.appearance = forceAqua ? NSAppearance(named: .aqua) : nil
    }
}
