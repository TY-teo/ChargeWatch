import SwiftUI

/// 面板内"充电上限"卡片——直接 SMC 控制（经 root helper），点一下即开。
/// 核心控件为原生 SwiftUI Slider（步进 5%，区间 50...90，对齐 SMCChargeLimiter.steps），
/// 配大号百分比读数、系统强调色填充、松手提交的弹簧动效与一格"已落定"的轻量缩放脉冲。
/// 仅在松手（onEditingChanged == false）写入 limiter，拖动途中不写盘，避免反复改写 SMC 配置。
struct SMCChargeLimitSection: View {
    @EnvironmentObject private var limiter: SMCChargeLimiter
    @EnvironmentObject private var stream: SampleStream
    @AppStorage("appTheme") private var themeRaw: String = AppTheme.classic.rawValue
    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .classic }

    private var soc: Int? { stream.latest?.stateOfChargePercent }

    /// 拖动期间的就地草稿值；仅松手时写入 limiter，外部变化经 onChange 回灌。
    @State private var draft: Double = 80
    /// 落定时的瞬时缩放脉冲，代替触觉反馈（macOS 13 无 sensoryFeedback）。
    @State private var commitPulse = false

    /// 与 SMCChargeLimiter.steps（50/60/70/80/90）对齐：5% 步进、50...90 区间。
    private static let sliderRange: ClosedRange<Double> = 50...90
    private static let sliderStep: Double = 5
    private static let tickValues: [Int] = SMCChargeLimiter.steps

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            header
            content
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(theme: theme)
        .onAppear { draft = clampToRange(Double(limiter.limit)) }
        .onChange(of: limiter.limit) { newValue in
            let synced = clampToRange(Double(newValue))
            if draft != synced { draft = synced }
        }
    }

    private var header: some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: AppIcon.chargeLimit)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColor.textSecondary)
                .accessibilityHidden(true)
            Text("充电上限")
                .font(AppFont.panelLabel)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            trailing.frame(minWidth: 56, alignment: .trailing)
        }
    }

    @ViewBuilder private var trailing: some View {
        if limiter.busy {
            ProgressView().controlSize(.small)
        } else if limiter.enabled {
            Text("\(limiter.limit)%")
                .font(AppFont.panelSubheadline)
                .foregroundStyle(AppColor.chargingActive)
        } else if let soc {
            Text("\(soc)%")
                .font(AppFont.panelSubheadline)
                .foregroundStyle(AppColor.textPrimary)
        } else {
            Text("—").font(AppFont.panelSubheadline).foregroundStyle(AppColor.textSecondary)
        }
    }

    @ViewBuilder private var content: some View {
        if !limiter.installed {
            enablePrompt
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                Toggle("启用充电上限", isOn: Binding(
                    get: { limiter.enabled },
                    set: { $0 ? limiter.enable(limit: limiter.limit) : limiter.disable() }
                ))
                .font(AppFont.panelBody)
                .disabled(limiter.busy)

                if limiter.enabled {
                    sliderControl
                } else {
                    disabledHint
                }
            }
        }
        if let err = limiter.lastError {
            Text(err).font(AppFont.panelCaption).foregroundStyle(AppColor.discharging)
        }
    }

    private var enablePrompt: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("开启后将电量保持在上限附近。首次需授权安装后台组件（仅一次）。")
                .font(AppFont.panelCaption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("开启充电上限") { limiter.enable(limit: 80) }
                .buttonStyle(.borderedProminent)
                .disabled(limiter.busy)
        }
    }

    private var sliderControl: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            readout
            Slider(
                value: $draft,
                in: Self.sliderRange,
                step: Self.sliderStep,
                onEditingChanged: { editing in
                    if !editing { commit() }
                }
            )
            .tint(AppColor.chargingActive)
            .disabled(limiter.busy)
            .accessibilityValue("\(Int(draft.rounded())) 百分比")
            tickRuler
        }
    }

    private var readout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(Int(draft.rounded()))")
                .font(AppFont.panelHeadline)
                .foregroundStyle(AppColor.chargingActive)
                .contentTransition(.numericText())
                .scaleEffect(commitPulse ? 1.06 : 1.0)
                .animation(.spring(response: 0.32, dampingFraction: 0.6), value: commitPulse)
            Text("%")
                .font(AppFont.unitSuffix)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            if let soc {
                Text("当前 \(soc)%")
                    .font(AppFont.panelCaption)
                    .foregroundStyle(AppColor.textSecondary)
                    .monospacedDigit()
            }
        }
    }

    private var tickRuler: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.tickValues.enumerated()), id: \.element) { index, tick in
                Text("\(tick)")
                    .font(AppFont.panelCaption)
                    .monospacedDigit()
                    .foregroundStyle(
                        Int(draft.rounded()) == tick ? AppColor.chargingActive : AppColor.textSecondary
                    )
                    .frame(maxWidth: .infinity,
                           alignment: tickAlignment(index: index, count: Self.tickValues.count))
            }
        }
        .accessibilityHidden(true)
    }

    private var disabledHint: some View {
        Text("已安装后台组件，打开开关即可设定上限。")
            .font(AppFont.panelCaption)
            .foregroundStyle(AppColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 松手提交：仅当落定值与当前 limiter.limit 不同才写盘，避免重复 setLimit。
    private func commit() {
        let value = Int(draft.rounded())
        guard value != limiter.limit else { return }
        limiter.setLimit(value)
        commitPulse = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            commitPulse = false
        }
    }

    private func clampToRange(_ value: Double) -> Double {
        min(max(value, Self.sliderRange.lowerBound), Self.sliderRange.upperBound)
    }

    private func tickAlignment(index: Int, count: Int) -> Alignment {
        if index == 0 { return .leading }
        if index == count - 1 { return .trailing }
        return .center
    }
}
