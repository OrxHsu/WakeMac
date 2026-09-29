import AppKit
import IOKit.ps
import UserNotifications
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
@MainActor final class LocalNotifier: NSObject, UNUserNotificationCenterDelegate {
    var enabled = false
    func configure() {
        let center = UNUserNotificationCenter.current(); center.delegate = self
        center.getNotificationSettings { [weak self] settings in
            Task { @MainActor in self?.enabled = settings.authorizationStatus == .authorized }
        }
    }
    func request() async -> Bool {
        enabled = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        return enabled
    }
    func send(_ text: String) {
        guard enabled else { return }
        let content = UNMutableNotificationContent(); content.title = "WakeMac"; content.body = text; content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
}
