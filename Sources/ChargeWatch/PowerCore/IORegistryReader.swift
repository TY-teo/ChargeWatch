import Foundation
import IOKit

final class IORegistryReader {

    func read() -> PowerSample {
        let timestamp = Date()
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))

        guard service != 0 else {
            return desktopFallback(timestamp: timestamp)
        }
        defer { IOObjectRelease(service) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS, let dict = propsRef?.takeRetainedValue() as? [String: Any] else {
            return desktopFallback(timestamp: timestamp)
        }

        let voltage = readInt(dict, "Voltage")
        let amperage = readSignedInt(dict, "Amperage")
        let instantAmperage = readSignedInt(dict, "InstantAmperage")
        let isCharging = (dict["IsCharging"] as? Bool) ?? false
        let externalConnected = (dict["ExternalConnected"] as? Bool) ?? false
        let soc = readInt(dict, "CurrentCapacity")

        let adapterDetails = dict["AdapterDetails"] as? [String: Any]
        let adapterRated = readInt(adapterDetails ?? [:], "Watts")
        let adapterDesc = formatAdapter(adapterDetails)

        // PowerTelemetryData 字段以无符号 64-bit 编码（充/放电时数值会落在 2^64 附近），
        // 必须按 int64 解码后取幅度——intValue(Int32) 会截断导致系统负载等出现负值。
        let telemetry = dict["PowerTelemetryData"] as? [String: Any]
        let systemLoadMilliwatts = readSignedInt(telemetry ?? [:], "SystemLoad").map { abs($0) }
        let batteryPowerMilliwatts = readSignedInt(telemetry ?? [:], "BatteryPower").map { abs($0) }
        let systemPowerInMilliwatts = readSignedInt(telemetry ?? [:], "SystemPowerIn").map { abs($0) }
        let adapterEfficiencyLossMilliwatts = readSignedInt(telemetry ?? [:], "AdapterEfficiencyLoss").map { abs($0) }

        // 电池功率幅度：优先瞬时遥测 BatteryPower（刚插电即实时反映），
        // 回退 电压×瞬时电流，再回退 电压×平均电流（顶层 Amperage 是多秒平均，会滞后）。
        let batteryMagnitudeWatts: Double
        if let bp = batteryPowerMilliwatts, bp > 0 {
            batteryMagnitudeWatts = Double(bp) / 1000.0
        } else if let v = voltage, let a = instantAmperage {
            batteryMagnitudeWatts = abs(Double(v) * Double(a) / 1_000_000.0)
        } else if let v = voltage, let a = amperage {
            batteryMagnitudeWatts = abs(Double(v) * Double(a) / 1_000_000.0)
        } else {
            batteryMagnitudeWatts = 0
        }
        // 方向：充电为正（充入电池），否则为负（放电）。
        let batteryWatts = isCharging ? batteryMagnitudeWatts : -batteryMagnitudeWatts

        let systemLoadWatts = systemLoadMilliwatts.map { Double($0) / 1000.0 }

        // 墙插输出功率（从插座拉了多少瓦）
        // 优先用 SMC 直接测量的 SystemPowerIn + AdapterEfficiencyLoss
        // SystemPowerIn = 0 时（采样间隙）fallback 到能量守恒 (load + battery)
        let wallOutputWatts: Double?
        if externalConnected {
            if let sysIn = systemPowerInMilliwatts, sysIn > 0 {
                let lossMw = adapterEfficiencyLossMilliwatts ?? 0
                wallOutputWatts = Double(sysIn + lossMw) / 1000.0
            } else if let load = systemLoadWatts {
                wallOutputWatts = max(0, load + batteryWatts)
            } else {
                wallOutputWatts = nil
            }
        } else {
            wallOutputWatts = nil
        }

        return PowerSample(
            timestamp: timestamp,
            isCharging: isCharging,
            externalConnected: externalConnected,
            hasBattery: true,
            batteryWatts: batteryWatts,
            wallOutputWatts: wallOutputWatts,
            systemLoadWatts: systemLoadWatts,
            voltageMillivolts: voltage,
            amperageMilliamps: amperage,
            stateOfChargePercent: soc,
            adapterRatedWatts: adapterRated,
            adapterDescription: adapterDesc
        )
    }

    private func desktopFallback(timestamp: Date) -> PowerSample {
        PowerSample(
            timestamp: timestamp,
            isCharging: false,
            externalConnected: true,
            hasBattery: false,
            batteryWatts: 0,
            wallOutputWatts: nil,
            systemLoadWatts: nil,
            voltageMillivolts: nil,
            amperageMilliamps: nil,
            stateOfChargePercent: nil,
            adapterRatedWatts: nil,
            adapterDescription: nil
        )
    }

    private func readInt(_ dict: [String: Any], _ key: String) -> Int? {
        guard let n = dict[key] as? NSNumber else { return nil }
        return n.intValue
    }

    private func readSignedInt(_ dict: [String: Any], _ key: String) -> Int? {
        guard let n = dict[key] as? NSNumber else { return nil }
        let bits = n.int64Value
        return Int(truncatingIfNeeded: bits)
    }

    private func formatAdapter(_ details: [String: Any]?) -> String? {
        guard let d = details, let watts = readInt(d, "Watts") else { return nil }
        let mv = readInt(d, "AdapterVoltage")
        let ma = readInt(d, "Current")
        let desc = (d["Description"] as? String)?.uppercased() ?? "ADAPTER"
        if let mv, let ma {
            let v = Double(mv) / 1000.0
            let a = Double(ma) / 1000.0
            return String(format: "%dW %@ · %.0fV/%.1fA", watts, desc, v, a)
        }
        return "\(watts)W \(desc)"
    }
}
