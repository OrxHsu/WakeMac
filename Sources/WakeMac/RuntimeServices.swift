import AppKit
import IOKit.ps
import UserNotifications
import Combine
import WakeMacCore

struct HistoryEntry: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var text: String
}
@MainActor final class HistoryStore {
    let url: URL?
    var entries: [HistoryEntry]
    init(url: URL?) {
        self.url = url
        entries = url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([HistoryEntry].self, from: $0) } ?? []
    }
    func append(_ text: String) {
        entries.insert(HistoryEntry(text: text), at: 0)
        entries = Array(entries.prefix(200))
        guard let url, let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
struct BatterySource {
    static func read() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let raw = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  raw[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = raw[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = raw[kIOPSMaxCapacityKey] as? Int, maximum > 0,
                  let state = raw[kIOPSPowerSourceStateKey] as? String,
                  state == kIOPSBatteryPowerValue || state == kIOPSACPowerValue else { continue }
            return BatteryReading(percent: Int(Double(current) / Double(maximum) * 100), onBattery: state == kIOPSBatteryPowerValue)
        }
        return nil
    }
}
@MainActor final class LocalNotifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var enabled = false
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var message = ""
    private let readAuthorization: () async -> UNAuthorizationStatus
    private let askAuthorization: () async throws -> Bool
    private let openSettings: (URL) -> Bool
    init(readAuthorization: @escaping () async -> UNAuthorizationStatus = { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus },
         askAuthorization: @escaping () async throws -> Bool = { try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) },
         openSettings: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.readAuthorization = readAuthorization; self.askAuthorization = askAuthorization; self.openSettings = openSettings
        super.init()
    }
    static var settingsURL: URL {
        var url = URLComponents(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        url.queryItems = [URLQueryItem(name: "id", value: Bundle.main.bundleIdentifier ?? "local.orx.WorkModes")]
        return url.url!
    }
    func refresh() async {
        authorizationStatus = await readAuthorization()
        enabled = authorizationStatus == .authorized || authorizationStatus == .provisional
    }
    func configure() {
        let center = UNUserNotificationCenter.current(); center.delegate = self
        Task { await refresh() }
    }
    func request() async -> Bool {
        await refresh()
        if authorizationStatus == .notDetermined {
            do { _ = try await askAuthorization(); await refresh() }
            catch { message = "通知授权请求失败：" + error.localizedDescription; return false }
        }
        if !enabled {
            let opened = openSettings(Self.settingsURL)
            message = opened ? "已打开通知设置，请选择 WakeMac 并允许通知。" : "无法打开通知设置，请在系统设置 → 通知中允许 WakeMac。"
        } else { message = "通知已开启。" }
        return enabled
    }
    func showSettings() {
        message = openSettings(Self.settingsURL) ? "已打开通知设置。" : "请打开系统设置 → 通知 → WakeMac。"
    }
    func send(_ text: String) {
        guard enabled else { return }
        let content = UNMutableNotificationContent(); content.title = "WakeMac"; content.body = text
        let name = UserDefaults.standard.string(forKey: "appearance.sound") ?? ""
        content.sound = name.isEmpty ? .default : UNNotificationSound(named: UNNotificationSoundName(rawValue: name))
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
}
