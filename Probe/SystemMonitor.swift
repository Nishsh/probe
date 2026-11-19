import Foundation
import UIKit
import Darwin

/// 采集设备可公开的运行时指标（iOS 沙盒内能拿到的真实数据）
final class SystemMonitor: ObservableObject {

    struct Snapshot {
        var cpuPercent: Double = 0
        var memUsedMB: Double = 0
        var memTotalMB: Double = 0
        var diskUsedGB: Double = 0
        var diskTotalGB: Double = 0
        var batteryLevel: Int = -1
        var batteryState: String = "—"
        var lowPower: Bool = false
        var thermal: String = "正常"
        var uptime: String = "—"
        var deviceModel: String = "—"
        var systemVersion: String = "—"
        var ipAddress: String = "—"
        var cpuCores: Int = 0

        var memPercent: Double {
            guard memTotalMB > 0 else { return 0 }
            return min(1, memUsedMB / memTotalMB)
        }

        var diskPercent: Double {
            guard diskTotalGB > 0 else { return 0 }
            return min(1, diskUsedGB / diskTotalGB)
        }
    }

    @Published private(set) var snap = Snapshot()

    private var timer: Timer?
    private var lastCPUSeconds: Double?
    private var lastSampleDate: Date?
    private let modelName: String

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        modelName = Self.hardwareModel()
        refresh()

        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        var s = snap

        // MARK: CPU（本进程占用率）
        if let now = Self.processCPUSeconds() {
            if let last = lastCPUSeconds, let lastDate = lastSampleDate {
                let dt = Date().timeIntervalSince(lastDate)
                if dt > 0 {
                    s.cpuPercent = min(max((now - last) / dt * 100.0, 0), 100)
                }
            }
            lastCPUSeconds = now
            lastSampleDate = Date()
        }
        s.cpuCores = ProcessInfo.processInfo.activeProcessorCount

        // MARK: 内存
        s.memUsedMB = Double(Self.residentBytes()) / 1_048_576
        s.memTotalMB = Double(ProcessInfo.processInfo.physicalMemory) / 1_048_576

        // MARK: 磁盘
        let home = URL(fileURLWithPath: NSHomeDirectory())
        if let v = try? home.resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                      .volumeAvailableCapacityForImportantUsageKey]) {
            let total = Double(v.volumeTotalCapacity ?? 0)
            let free = Double(v.volumeAvailableCapacityForImportantUsage ?? 0)
            s.diskTotalGB = total / 1_073_741_824
            s.diskUsedGB = max(0, total - free) / 1_073_741_824
        }

        // MARK: 电池
        let dev = UIDevice.current
        s.batteryLevel = dev.batteryLevel < 0 ? -1 : Int((dev.batteryLevel * 100).rounded())
        switch dev.batteryState {
        case .charging: s.batteryState = "充电中"
        case .full: s.batteryState = "已充满"
        case .unplugged: s.batteryState = "使用电池"
        default: s.batteryState = "—"
        }
        s.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

        // MARK: 温控状态
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: s.thermal = "正常"
        case .fair: s.thermal = "偏热"
        case .serious: s.thermal = "较热 · 可能降频"
        case .critical: s.thermal = "过热"
        @unknown default: s.thermal = "—"
        }

        // MARK: 其他
        s.uptime = Self.formatUptime(ProcessInfo.processInfo.systemUptime)
        s.deviceModel = modelName
        s.systemVersion = "\(dev.systemName) \(dev.systemVersion)"
        s.ipAddress = Self.wifiAddress() ?? "未连接"

        snap = s
    }

    // MARK: - 底层采集

    private static func processCPUSeconds() -> Double? {
        var info = task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<task_basic_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO), raw, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1_000_000
        let sys = Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1_000_000
        return user + sys
    }

    private static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), raw, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }

    private static func hardwareModel() -> String {
        var uts = utsname()
        uname(&uts)
        let mirror = Mirror(reflecting: uts.machine)
        var identifier = ""
        for child in mirror.children {
            if let value = child.value as? Int8, value != 0 {
                identifier.append(Character(UnicodeScalar(UInt8(value))))
            }
        }
        return identifier.isEmpty ? "iPhone" : identifier
    }

    private static func wifiAddress() -> String? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
        defer { freeifaddrs(addrs) }

        var cursor = first
        while true {
            let ifa = cursor.pointee
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET) {
                let name = String(cString: ifa.ifa_name)
                if name == "en0" {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let len = socklen_t(addr.pointee.sa_len)
                    if getnameinfo(addr, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        return String(cString: host)
                    }
                }
            }
            guard let next = ifa.ifa_next else { break }
            cursor = next
        }
        return nil
    }

    private static func formatUptime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)天 \(hours)小时 \(minutes)分" }
        if hours > 0 { return "\(hours)小时 \(minutes)分" }
        return "\(minutes)分钟"
    }
}
