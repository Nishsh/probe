import SwiftUI

struct ContentView: View {
    @StateObject private var monitor = SystemMonitor()

    private let accentCyan = Color(red: 0.29, green: 0.85, blue: 0.88)
    private let accentMint = Color(red: 0.42, green: 0.90, blue: 0.63)
    private let accentAmber = Color(red: 1.00, green: 0.72, blue: 0.30)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.09),
                                    Color(red: 0.09, green: 0.10, blue: 0.15)],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    gauges
                    infoCard
                    footer
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 顶部信息

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("探针")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Text(monitor.snap.uptime)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
            }
            Text("\(monitor.snap.deviceModel) · \(monitor.snap.systemVersion)")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.45))
        }
        .padding(.top, 6)
    }

    // MARK: - 三个环形指标

    private var gauges: some View {
        HStack(spacing: 10) {
            RingGauge(title: "CPU",
                      value: monitor.snap.cpuPercent / 100,
                      text: "\(Int(monitor.snap.cpuPercent))%",
                      caption: "\(monitor.snap.cpuCores) 核",
                      tint: accentCyan)

            RingGauge(title: "内存",
                      value: monitor.snap.memPercent,
                      text: "\(Int(monitor.snap.memUsedMB))M",
                      caption: String(format: "%.0fG 设备", monitor.snap.memTotalMB / 1024),
                      tint: accentMint)

            RingGauge(title: "磁盘",
                      value: monitor.snap.diskPercent,
                      text: String(format: "%.0fG", monitor.snap.diskUsedGB),
                      caption: String(format: "共 %.0fG", monitor.snap.diskTotalGB),
                      tint: accentAmber)
        }
    }

    // MARK: - 明细卡片

    private var infoCard: some View {
        VStack(spacing: 0) {
            InfoRow(label: "电池电量",
                    value: monitor.snap.batteryLevel < 0 ? "—" : "\(monitor.snap.batteryLevel)%")
            divider
            InfoRow(label: "供电状态", value: monitor.snap.batteryState)
            divider
            InfoRow(label: "低电量模式", value: monitor.snap.lowPower ? "已开启" : "关闭")
            divider
            InfoRow(label: "温控状态", value: monitor.snap.thermal)
            divider
            InfoRow(label: "本机 IP", value: monitor.snap.ipAddress)
            divider
            InfoRow(label: "磁盘可用",
                    value: String(format: "%.1f GB", max(0, monitor.snap.diskTotalGB - monitor.snap.diskUsedGB)))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
    }

    private var footer: some View {
        Text("数据每秒刷新 · 纯本地采集，不联网")
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.3))
            .padding(.top, 2)
    }
}

// MARK: - 环形仪表

struct RingGauge: View {
    let title: String
    let value: Double
    let text: String
    let caption: String
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.07), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0.002, min(1, value))))
                    .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.35), value: value)

                VStack(spacing: 1) {
                    Text(text)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(title)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 6)
            }
            .frame(width: 94, height: 94)

            Text(caption)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.35))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
    }
}

// MARK: - 单行信息

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.55))
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.92))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 11)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
