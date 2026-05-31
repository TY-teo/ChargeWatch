import SwiftUI
import Charts

/// 菜单栏弹出面板。采用 StayAwake 同款"系统玻璃"风格：vibrancy 主题下用系统 popover
/// 材质透出桌面，内部分组全部使用原生 `GroupBox`，控件用原生 `LabeledContent` /
/// `Button .controlSize(.large)`，文字一律 `.primary` / `.secondary`；仅保留唯一一处
/// 语义强调色（充电功率用系统级绿色），其余跟随系统外观。固定 360x640 尺寸、操作行钉底，
/// 避免 sparkline 每秒重绘引起的外框抖动。
struct MenuBarPanel: View {
    let onOpenHistory: () -> Void
    let onOpenSettings: () -> Void
    let onExport: () -> Void
    let onQuit: () -> Void

    @EnvironmentObject private var stream: SampleStream
    @AppStorage("appTheme") private var themeRaw: String = AppTheme.classic.rawValue

    private var theme: AppTheme {
        AppTheme(rawValue: themeRaw) ?? .classic
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            statusBanner
            metricsGroup
            sparklineGroup
            SMCChargeLimitSection()
            Spacer(minLength: 0)
            Divider()
            actionRow
        }
        .padding(AppSpacing.l)
        .frame(width: 360, height: 640, alignment: .top)
        .panelBackground(theme: theme)
    }

    // MARK: - 状态横幅

    private var statusBanner: some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: bannerIcon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(stream.latest?.status.displayName ?? "采集中")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(bannerHeadline)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(bannerHeadlineColor)
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(.horizontal, 2)
    }

    private var bannerIcon: String {
        switch stream.latest?.status {
        case .charging: return AppIcon.chargingActive
        case .acPaused: return AppIcon.chargingPaused
        case .discharging: return AppIcon.batterySymbol(for: stream.latest?.stateOfChargePercent)
        case .desktop: return AppIcon.powerPlug
        case .none: return AppIcon.chargingPaused
        }
    }

    /// 唯一一处语义强调色：充电中的功率读数用系统级绿色，其余跟随系统主文字色。
    private var bannerHeadlineColor: Color {
        stream.latest?.status == .charging ? AppColor.chargingActive : .primary
    }

    private var bannerHeadline: String {
        guard let s = stream.latest else { return "--" }
        switch s.status {
        case .charging:
            return String(format: "%.1f W", s.batteryWatts)
        case .acPaused:
            return s.stateOfChargePercent.map { "AC · \($0)%" } ?? "AC"
        case .discharging:
            return s.stateOfChargePercent.map { "电池 · \($0)%" } ?? "放电中"
        case .desktop:
            return s.systemLoadWatts.map { String(format: "系统 %.1f W", $0) } ?? "市电"
        }
    }

    // MARK: - 指标分组（原生 GroupBox + LabeledContent 行）

    private var metricsGroup: some View {
        GroupBox {
            VStack(spacing: AppSpacing.s) {
                metricRow(label: "充入电池",
                          value: stream.latest?.batteryWatts,
                          unit: "W",
                          formatter: wattText,
                          highlight: stream.latest?.status == .charging)
                Divider()
                metricRow(label: "墙插输出",
                          value: stream.latest?.wallOutputWatts,
                          unit: "W",
                          formatter: wattText,
                          highlight: false)
                Divider()
                metricRow(label: "系统负载",
                          value: stream.latest?.systemLoadWatts,
                          unit: "W",
                          formatter: wattText,
                          highlight: false)
                Divider()
                metricRow(label: "电池电量",
                          value: stream.latest?.stateOfChargePercent.map(Double.init),
                          unit: "%",
                          formatter: percentText,
                          highlight: false)
                Divider()
                adapterRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metricRow(label: String,
                           value: Double?,
                           unit: String,
                           formatter: (Double) -> String,
                           highlight: Bool) -> some View {
        LabeledContent {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value.map(formatter) ?? "--")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(highlight ? AppColor.chargingActive : .primary)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text(label)
                .foregroundStyle(.secondary)
        }
    }

    private var adapterRow: some View {
        LabeledContent {
            Text(stream.latest?.adapterDescription ?? "未检测到适配器")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        } label: {
            Label("适配器", systemImage: AppIcon.powerPlug)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
        }
    }

    // MARK: - 最近 60 秒（原生 GroupBox 包裹，固定高度避免抖动）

    private var sparklineGroup: some View {
        let points = Array(stream.rolling.suffix(60).enumerated().map(SparkPoint.init))
        let lastID = points.last?.id
        let currentW = points.last?.y
        return GroupBox {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text("最近 60 秒")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let currentW {
                        Text(String(format: "%.1f W", currentW))
                            .font(.callout.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(sparkColor)
                    }
                }
                .font(.subheadline)

                Chart(points) { p in
                    LineMark(x: .value("idx", p.x), y: .value("W", p.y))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(sparkColor)
                    AreaMark(x: .value("idx", p.x), y: .value("W", p.y))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(sparkColor.opacity(0.18))
                    if p.id == lastID {
                        PointMark(x: .value("idx", p.x), y: .value("W", p.y))
                            .foregroundStyle(sparkColor)
                            .symbolSize(26)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(.separator)
                        AxisValueLabel {
                            if let w = value.as(Double.self) {
                                Text("\(Int(w.rounded()))")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 64)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// sparkline 描边色：充电绿、放电橙、其余系统次要色（仅图表内使用语义色）。
    private var sparkColor: Color {
        switch stream.latest?.status {
        case .charging: return AppColor.chargingActive
        case .discharging: return AppColor.discharging
        default: return .secondary
        }
    }

    // MARK: - 操作行（钉底）

    private var actionRow: some View {
        HStack(spacing: 0) {
            ActionButton(icon: AppIcon.history, label: "完整历史", action: onOpenHistory)
            ActionButton(icon: AppIcon.export, label: "导出 CSV", action: onExport)
            ActionButton(icon: AppIcon.settings, label: "设置", action: onOpenSettings)
            ActionButton(icon: AppIcon.quit, label: "退出", action: onQuit)
        }
    }

    private func wattText(_ value: Double) -> String { String(format: "%.1f", value) }
    private func percentText(_ value: Double) -> String { "\(Int(value))" }
}

private struct SparkPoint: Identifiable {
    let id: Int
    let x: Int
    let y: Double
    init(_ entry: EnumeratedSequence<ArraySlice<PowerSample>>.Element) {
        self.id = entry.offset
        self.x = entry.offset
        let sample = entry.element
        self.y = sample.status == .charging ? sample.batteryWatts : (sample.systemLoadWatts ?? abs(sample.batteryWatts))
    }
}

/// 操作行按钮：图标在上、文字在下，悬停时浅底反馈，全部使用系统语义文字色。
private struct ActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                Text(label)
                    .font(.caption)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 46)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: AppRadius.s, style: .continuous)
                    .fill(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
    }
}
