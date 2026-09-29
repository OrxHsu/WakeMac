import AppKit
import CoreGraphics
import IOKit
import WakeMacCore
import WakeMacPower

actor MacBackend: ModeBackend {
    private func command(_ path: String, _ args: [String], timeout: TimeInterval = 20) async throws -> String {
        try await Task.detached(priority: .userInitiated) { try CommandRunner.run(path, args, timeout: timeout) }.value
    }
    private let assertion = NativeSleepAssertion()
    private let helper = PowerHelperClient()
    private var backgroundRequested = false
    func snapshot() async throws -> Snapshot {
        if backgroundRequested {
            do { try await helper.renew() }
            catch {
                // If the helper expires or disconnects, do not leave an
                // invisible desktop inhibitor behind in the main process.
                backgroundRequested = false
                let reason = error.localizedDescription
                do { try assertion.release() }
                catch { throw ModeError("合盖会话已失效；释放原生保活也失败：" + error.localizedDescription) }
                throw ModeError("合盖会话已失效，已释放本应用的保活。\n" + reason)
            }
        }
        let power = try await command("/usr/bin/pmset", ["-g"])
        let policy = try await command("/usr/sbin/sysadminctl", ["-screenLock", "status"])
        return Snapshot(sleepDisabled: SystemParsing.sleepDisabled(power), lockPolicy: SystemParsing.lockPolicy(policy),
                        idleSleepPrevented: assertion.active, displaySleepAllowed: true, backgroundLeaseActive: backgroundRequested)
    }
    func configurePower(_ mode: WorkMode) async throws {
        if mode != .background {
            try assertion.release()
            if backgroundRequested {
                do { try await helper.setBackground(false) }
                catch {
                    // An unapproved/unavailable helper cannot leave us in an
                    // error state when system readback already confirms sleep.
                    let power = try await command("/usr/bin/pmset", ["-g"])
                    guard SystemParsing.sleepDisabled(power) == false else { throw error }
                }
                backgroundRequested = false
            }
        }
        if mode == .background {
            backgroundRequested = true
            try await helper.setBackground(true)
        }
        let power = try await command("/usr/bin/pmset", ["-g"])
        guard SystemParsing.sleepDisabled(power) == (mode == .background) else {
            throw ModeError("系统防休眠状态不一致。请先在其他保活程序中恢复休眠，再重新选择模式。")
        }
        if mode != .normal { try assertion.acquire() }
    }
    func requestLockPolicy(_ policy: LockPolicy) async {
        await MainActor.run {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension") { NSWorkspace.shared.open(url) }
        }
    }
    func sleepNow() async throws { _ = try await command("/usr/bin/pmset", ["sleepnow"]) }
}

struct DisplayState {
    var lidClosed: Bool?
    var builtInAsleep: Bool?
    var sessionLocked: Bool?
    static func read() -> DisplayState {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        var lid: Bool?
        if root != 0 {
            lid = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
            IOObjectRelease(root)
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        var asleep: Bool?
        if CGGetOnlineDisplayList(16, &ids, &count) == .success {
            if let id = ids.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }) { asleep = CGDisplayIsAsleep(id) != 0 }
        }
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let locked = session?["CGSSessionScreenIsLocked"] as? Bool
        return DisplayState(lidClosed: lid, builtInAsleep: asleep, sessionLocked: locked)
    }
}
