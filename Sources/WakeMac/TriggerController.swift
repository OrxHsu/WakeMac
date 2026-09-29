import Foundation
import Combine
import WakeMacCore
import Darwin

enum TriggerKind: String, Codable, CaseIterable, Identifiable {
    case externalDisplay, displayMirroring, usbDevice, bluetoothDevice, appRunning, appFrontmost
    case batteryCharging, batteryAbove, acConnected, acDisconnected, ipAddress, wifiSSID, ciscoVPN, dnsServer
    case headphones, audioOutput, mountedVolume, cpuAbove, idleAbove
    var id: String { rawValue }
    var title: String {
        switch self {
        case .externalDisplay: return "连接外接显示器"
        case .displayMirroring: return "显示器镜像"
        case .usbDevice: return "连接 USB 设备"
        case .bluetoothDevice: return "连接蓝牙设备"
        case .appRunning: return "指定应用正在运行"
        case .appFrontmost: return "指定应用位于前台"
        case .batteryCharging: return "电池正在充电"
        case .batteryAbove: return "电量高于百分比"
        case .acConnected: return "已连接电源"
        case .acDisconnected: return "已断开电源"
        case .ipAddress: return "拥有指定 IP 地址"
        case .wifiSSID: return "连接指定 Wi-Fi"
        case .ciscoVPN: return "已连接 Cisco VPN"
        case .dnsServer: return "使用指定 DNS 服务器"
        case .headphones: return "使用耳机输出"
        case .audioOutput: return "使用指定音频输出"
        case .mountedVolume: return "已挂载指定磁盘"
        case .cpuAbove: return "CPU 使用率高于百分比"
        case .idleAbove: return "空闲时间超过秒数"
        }
    }
    var requiresValue: Bool {
        [.usbDevice, .bluetoothDevice, .appRunning, .appFrontmost, .batteryAbove, .ipAddress, .wifiSSID, .dnsServer, .audioOutput, .mountedVolume, .cpuAbove, .idleAbove].contains(self)
    }
    var hint: String {
        switch self {
        case .appRunning, .appFrontmost: return "应用 Bundle ID，例如 com.apple.Safari"
        case .usbDevice: return "设备名称或 registry ID（见当前观测）"
        case .bluetoothDevice: return "设备名称或蓝牙地址"
        case .batteryAbove, .cpuAbove: return "0–100；必须严格高于此值"
        case .idleAbove: return "1–86400 秒；必须严格超过此值"
        case .ipAddress, .dnsServer: return "完整 IPv4 或 IPv6 地址"
        case .wifiSSID: return "完整 Wi-Fi 网络名称（区分大小写）"
        case .audioOutput: return "设备名称或 UID（见当前观测）"
        case .mountedVolume: return "磁盘名称或完整挂载路径"
        default: return "无需额外参数"
        }
    }
}

struct TriggerCondition: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: TriggerKind = .externalDisplay
    var value = ""
    var validationError: String? {
        guard kind.requiresValue else { return nil }
        let input = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return "请填写\(kind.hint)。" }
        switch kind {
        case .batteryAbove, .cpuAbove:
            guard let number = Double(input), number.isFinite, number >= 0, number < 100 else { return "百分比必须在 0（含）至 100（不含）之间。" }
        case .idleAbove:
            guard let number = Double(input), number.isFinite, number >= 1, number <= 86400 else { return "空闲秒数必须在 1–86400 之间。" }
        case .ipAddress, .dnsServer:
            guard Self.isIPAddress(input) else { return "请输入完整的 IPv4 或 IPv6 地址。" }
        case .appRunning, .appFrontmost:
            guard input.contains("."), !input.contains(where: { $0.isWhitespace }), !input.contains("/") else { return "请使用应用的 Bundle ID，不能使用进程名或路径。" }
        default: break
        }
        return nil
    }
    static func isIPAddress(_ input: String) -> Bool {
        var v4 = in_addr(), v6 = in6_addr()
        return input.withCString { inet_pton(AF_INET, $0, &v4) == 1 || inet_pton(AF_INET6, $0, &v6) == 1 }
    }
}

enum TriggerCombination: String, Codable, CaseIterable { case all, any }
struct TriggerRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "新触发规则"
    var mode: WorkMode = .desk
    var enabled = false
    var combination: TriggerCombination = .all
    var conditions = [TriggerCondition()]
    var validationError: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写规则名称。" }
        if mode == .normal { return "触发规则只能选择桌面工作或后台工作。" }
        if conditions.isEmpty { return "每条规则至少需要一个条件。" }
        if Set(conditions.map(\.id)).count != conditions.count { return "条件标识重复，请重新添加条件。" }
        return conditions.compactMap(\.validationError).first
    }
    func matches(_ results: [UUID: TriggerConditionResult]) -> Bool {
        guard enabled, validationError == nil else { return false }
        let matches = conditions.map { results[$0.id]?.state == .matched }
        return combination == .all ? matches.allSatisfy { $0 } : matches.contains(true)
    }
}

enum TriggerMatchState: String { case matched, unmatched, unknown }
struct TriggerConditionResult: Equatable {
    var state: TriggerMatchState
    var detail: String
}

@MainActor final class TriggerController: ObservableObject {
    @Published private(set) var rules: [TriggerRule]
    @Published private(set) var observations: [UUID: TriggerConditionResult] = [:]
    @Published private(set) var status = "尚未启用自动触发规则。"
    @Published private(set) var snapshot = TriggerSnapshot()
    @Published private(set) var lastObservedAt: Date?
    private let preferences: UserDefaults
    private let source: any TriggerObservationSource
    private var revision = 0
    private static let storageKey = "NativeTriggerRules.v1"
    init(preferences: UserDefaults, source: (any TriggerObservationSource)? = nil) {
        self.preferences = preferences
        self.source = source ?? NativeTriggerObservations()
        rules = preferences.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode([TriggerRule].self, from: $0) } ?? []
    }
    @discardableResult func save(_ rule: TriggerRule) -> String? {
        if let error = rule.validationError { return error }
        if let index = rules.firstIndex(where: { $0.id == rule.id }) { rules[index] = rule }
        else { rules.append(rule) }
        persist(); return nil
    }
    func remove(_ id: UUID) { rules.removeAll { $0.id == id }; persist() }
    func setEnabled(_ id: UUID, _ enabled: Bool) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        guard !enabled || rules[index].validationError == nil else { return }
        rules[index].enabled = enabled; persist()
    }
    private func persist() {
        revision += 1
        if let data = try? JSONEncoder().encode(rules) { preferences.set(data, forKey: Self.storageKey) }
        if !rules.contains(where: \.enabled) { status = "尚未启用自动触发规则。"; observations = [:] }
    }
    func matchingRules(now: Date, battery: BatteryReading?) async -> [TriggerRule] {
        let enabled = rules.filter { $0.enabled && $0.validationError == nil }
        guard !enabled.isEmpty else { observations = [:]; status = "尚未启用自动触发规则。"; return [] }
        let observedRevision = revision
        await observe(rules: enabled, now: now, battery: battery)
        guard revision == observedRevision else { observations = [:]; return [] }
        let matches = enabled.filter { $0.matches(observations) }
        status = matches.isEmpty ? "没有规则满足条件。" : "满足条件：" + matches.map(\.name).joined(separator: "、")
        return matches
    }
    func refreshDiagnostics() async { await observe(rules: rules, now: Date(), battery: nil) }
    private func observe(rules: [TriggerRule], now: Date, battery: BatteryReading?) async {
        let kinds = Set(rules.flatMap(\.conditions).map(\.kind))
        snapshot = await source.read(kinds: kinds, now: now)
        if let battery {
            snapshot.batteryPercent = (0...100).contains(battery.percent) ? battery.percent : nil
            snapshot.acConnected = !battery.onBattery
        }
        lastObservedAt = now
        var results: [UUID: TriggerConditionResult] = [:]
        for condition in rules.flatMap(\.conditions) { results[condition.id] = snapshot.evaluate(condition) }
        observations = results
    }
    /// Editor preview is read-only and never saves or evaluates an unsaved rule.
    func preview(kinds: Set<TriggerKind>) async -> TriggerSnapshot { await source.read(kinds: kinds, now: Date()) }
    static func applicationBundleIdentifier(at url: URL) -> String? {
        guard url.pathExtension.lowercased() == "app", let id = Bundle(url: url)?.bundleIdentifier,
              TriggerCondition(kind: .appRunning, value: id).validationError == nil else { return nil }
        return id
    }
    func openPermissionSettings(for kind: TriggerKind) { source.openPermissionSettings(for: kind) }
    func requestPermission(for kind: TriggerKind) { source.requestPermission(for: kind) }
}
