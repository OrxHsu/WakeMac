import Foundation
import Combine
import AppKit

@MainActor final class BehaviorPreferences: ObservableObject {
    @Published var startAtLaunch: Bool { didSet { save() } }
    @Published var startAfterWake: Bool { didSet { save() } }
    @Published var defaultIndefinite: Bool { didSet { save() } }
    @Published var defaultMinutes: Double { didSet { save() } }
    @Published var reminderEnabled: Bool { didSet { save() } }
    @Published var reminderMinutes: Double { didSet { save() } }
    @Published var lidToneEnabled: Bool { didSet { save() } }
    @Published var lidToneRepeat: Bool { didSet { save() } }
    @Published var lidToneSeconds: Double { didSet { save() } }
    @Published var lidToneVolume: Double { didSet { save() } }
    @Published var statisticsEnabled: Bool { didSet { previousSample = nil; save() } }
    @Published private(set) var awakeSeconds: Double
    @Published private(set) var lidSeconds: Double
    @Published private(set) var activations: Int
    private let preferences: UserDefaults
    private var previousSample: Date?
    private var previouslyWorking = false
    private var previouslyClosed = false
    private var lastReminder: Date?
    private var lastTone: Date?
    private var lastSave: Date?
    enum Action: Equatable { case reminder, lidTone }

    init(preferences: UserDefaults) {
        self.preferences = preferences
        startAtLaunch = preferences.bool(forKey: "behavior.startAtLaunch")
        startAfterWake = preferences.bool(forKey: "behavior.startAfterWake")
        defaultIndefinite = preferences.object(forKey: "behavior.defaultIndefinite") as? Bool ?? true
        defaultMinutes = preferences.object(forKey: "behavior.defaultMinutes") as? Double ?? 60
        reminderEnabled = preferences.bool(forKey: "behavior.reminderEnabled")
        reminderMinutes = preferences.object(forKey: "behavior.reminderMinutes") as? Double ?? 60
        lidToneEnabled = preferences.bool(forKey: "behavior.lidToneEnabled")
        lidToneRepeat = preferences.bool(forKey: "behavior.lidToneRepeat")
        lidToneSeconds = preferences.object(forKey: "behavior.lidToneSeconds") as? Double ?? 60
        lidToneVolume = preferences.object(forKey: "behavior.lidToneVolume") as? Double ?? 0.5
        statisticsEnabled = preferences.bool(forKey: "behavior.statisticsEnabled")
        awakeSeconds = max(0, preferences.double(forKey: "statistics.awakeSeconds"))
        lidSeconds = max(0, preferences.double(forKey: "statistics.lidSeconds"))
        activations = max(0, preferences.integer(forKey: "statistics.activations"))
    }
    func sample(working: Bool, closed: Bool, docked: Bool, now: Date) -> [Action] {
        var actions: [Action] = []
        if statisticsEnabled {
            if working && !previouslyWorking { activations += 1 }
            if working, previouslyWorking, let previousSample {
                let delta = now.timeIntervalSince(previousSample)
                // Do not count suspension, a clock correction, or unobserved gaps as verified work.
                if delta >= 0 && delta <= 15 { awakeSeconds += delta; if closed && previouslyClosed { lidSeconds += delta } }
            }
            previousSample = now
            if lastSave == nil || now.timeIntervalSince(lastSave!) >= 60 || working != previouslyWorking { saveStatistics(); lastSave = now }
        }
        if working && reminderEnabled && reminderMinutes.isFinite && (1...10080).contains(reminderMinutes) {
            if let lastReminder, now.timeIntervalSince(lastReminder) >= reminderMinutes * 60 { actions.append(.reminder); self.lastReminder = now }
            else if lastReminder == nil { lastReminder = now }
        } else { lastReminder = nil }
        if working && closed && !docked && lidToneEnabled {
            let interval = lidToneSeconds.isFinite ? min(max(lidToneSeconds, 5), 86400) : 60
            if lastTone == nil || (lidToneRepeat && now.timeIntervalSince(lastTone!) >= interval) { actions.append(.lidTone); lastTone = now }
        } else { lastTone = nil }
        previouslyWorking = working; previouslyClosed = closed
        return actions
    }
    func saveStatistics() {
        preferences.set(awakeSeconds, forKey: "statistics.awakeSeconds"); preferences.set(lidSeconds, forKey: "statistics.lidSeconds")
        preferences.set(activations, forKey: "statistics.activations")
    }
    func resetStatistics() {
        awakeSeconds = 0; lidSeconds = 0; activations = 0; previousSample = nil; saveStatistics()
    }
    private func save() {
        for (key, value) in [("startAtLaunch", startAtLaunch), ("startAfterWake", startAfterWake), ("defaultIndefinite", defaultIndefinite), ("reminderEnabled", reminderEnabled), ("lidToneEnabled", lidToneEnabled), ("lidToneRepeat", lidToneRepeat), ("statisticsEnabled", statisticsEnabled)] { preferences.set(value, forKey: "behavior." + key) }
        for (key, value) in [("defaultMinutes", defaultMinutes), ("reminderMinutes", reminderMinutes), ("lidToneSeconds", lidToneSeconds), ("lidToneVolume", lidToneVolume)] { preferences.set(value, forKey: "behavior." + key) }
        if !statisticsEnabled { saveStatistics() }
    }
}

extension AppModel {
    func beginDefaultSession() async {
        guard !busy, !sessions.isStarting, !sessions.isActive, !verifiedWork else { return }
        sessions.endCondition = behavior.defaultIndefinite ? .indefinite : .duration
        sessions.durationMinutes = behavior.defaultMinutes
        await sessions.start()
    }
    func tickBehavior(now: Date) {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16), count: UInt32 = 0
        let hasExternal = CGGetOnlineDisplayList(16, &ids, &count) == .success && ids.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
        let docked = battery?.onBattery == false && hasExternal
        for action in behavior.sample(working: verifiedWork, closed: runsWithLidClosed && display.lidClosed == true, docked: docked, now: now) {
            switch action {
            case .reminder: record("工作会话仍在运行：" + headline, notify: true)
            case .lidTone: appearance.playLidTone(volume: behavior.lidToneVolume)
            }
        }
    }
}
