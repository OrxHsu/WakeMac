import Foundation

public struct BatteryReading: Equatable, Sendable {
    public let percent: Int
    public let onBattery: Bool
    public init(percent: Int, onBattery: Bool) { self.percent = percent; self.onBattery = onBattery }
}
public enum AutomationAction: Equatable { case restoreNormal, batteryWarning(Int), batteryCountdown, sleepForBattery, sleepForJob }
public struct AutomationPolicy {
    public var deadline: Date?
    public var batteryEnabled = true
    public var batteryThreshold = 20
    public private(set) var batterySleepAt: Date?
    public private(set) var jobSleepAt: Date?
    public private(set) var jobID: UUID?
    public private(set) var jobArmed = false
    private var batterySuppressed = false
    private var batteryWarned = false
    public init() {}
    public mutating func resetBatterySession() { batterySleepAt = nil; batterySuppressed = false; batteryWarned = false }
    public mutating func cancelBatterySleep() { batterySleepAt = nil; batterySuppressed = true }
    public mutating func cancelJobSleep() { jobArmed = false; jobSleepAt = nil }
    public mutating func beginJob() -> UUID {
        let id = UUID(); jobID = id; jobArmed = true; jobSleepAt = nil; return id
    }
    public mutating func finishJob(id: UUID, success: Bool, now: Date) {
        guard jobID == id else { return }
        jobID = nil
        jobSleepAt = success && jobArmed ? now.addingTimeInterval(60) : nil
        if !success { jobArmed = false }
    }
    public mutating func evaluate(now: Date, mode: WorkMode?, battery: BatteryReading?) -> [AutomationAction] {
        guard mode == .desk || mode == .background else {
            deadline = nil; batterySleepAt = nil; jobSleepAt = nil; return []
        }
        if let end = deadline, now >= end {
            deadline = nil; cancelJobSleep(); cancelBatterySleep(); return [.restoreNormal]
        }
        var actions: [AutomationAction] = []
        if !batteryEnabled { batterySleepAt = nil }
        else if let b = battery, (0...100).contains(b.percent) {
            if !b.onBattery { resetBatterySession() }
            else if !batterySuppressed {
                let threshold = min(50, max(5, batteryThreshold))
                if b.percent <= threshold {
                    if let end = batterySleepAt {
                        if now >= end { cancelBatterySleep(); cancelJobSleep(); return [.sleepForBattery] }
                    } else {
                        batterySleepAt = now.addingTimeInterval(60); batteryWarned = true
                        actions.append(.batteryCountdown)
                    }
                } else {
                    batterySleepAt = nil
                    if b.percent <= threshold + 5 && !batteryWarned { batteryWarned = true; actions.append(.batteryWarning(b.percent)) }
                    if b.percent > threshold + 5 { batteryWarned = false }
                }
            }
        } else { batterySleepAt = nil }
        if let end = jobSleepAt, now >= end { cancelJobSleep(); actions.append(.sleepForJob) }
        return actions
    }
    public var nextDeadline: Date? { [deadline, batterySleepAt, jobSleepAt].compactMap { $0 }.min() }
}
