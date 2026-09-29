import AppKit
import CoreGraphics
import IOKit
import WakeMacCore

actor MacBackend: ModeBackend {
    private func command(_ path: String, _ args: [String], timeout: TimeInterval = 20) async throws -> String {
        try await Task.detached(priority: .userInitiated) { try CommandRunner.run(path, args, timeout: timeout) }.value
    }
    private func amp(_ body: String) async throws -> String {
        guard FileManager.default.fileExists(atPath: "/Applications/Amphetamine.app") else { throw ModeError("请先安装 Amphetamine。") }
        // This is the app's documented scripting API, never System Events UI scripting.
        let script = "with timeout of 12 seconds\ntell application \"/Applications/Amphetamine.app\"\n" + body + "\nend tell\nend timeout"
        do { return try await command("/usr/bin/osascript", ["-e", script], timeout: 30) }
        catch { throw ModeError("无法控制 Amphetamine。请检查系统设置 → 隐私与安全性 → 自动化，允许 WakeMac控制 Amphetamine。\n" + error.localizedDescription) }
    }
    func snapshot() async throws -> Snapshot {
        let power = try await command("/usr/bin/pmset", ["-g"])
        let policy = try await command("/usr/sbin/sysadminctl", ["-screenLock", "status"])
        let raw = try await amp("return {(session is active), (Triggers are enabled), (display sleep allowed), (closed display mode enabled), (session is Trigger), (session time remaining)}")
        let duration = try SystemParsing.sessionDuration(raw)
        let booleans = raw.components(separatedBy: ",").prefix(5).joined(separator: ",")
        let fields = try SystemParsing.amphetamine(booleans)
        return Snapshot(sleepDisabled: SystemParsing.sleepDisabled(power), lockPolicy: SystemParsing.lockPolicy(policy), sessionActive: fields[0], triggersEnabled: fields[1], displaySleepAllowed: fields[2], closedDisplayEnabled: fields[3], sessionIsTrigger: fields[4], sessionTimeRemaining: duration)
    }
    func configurePower(_ mode: WorkMode) async throws {
        var failures: [String] = []
        let body: String
        switch mode {
        case .normal:
            body = "disable Triggers\nend session\ndisable closed display mode"
        case .background, .desk:
            body = "disable Triggers\nend session\nstart new session with options {duration:0, interval:0, displaySleepAllowed:true}\nallow display sleep\nprevent screen saver\n" + (mode == .background ? "enable closed display mode" : "disable closed display mode")
        }
        do { _ = try await amp(body) } catch { failures.append(error.localizedDescription) }
        // Reuse only the two narrow permissions already installed by official Power Protect.
        // Clear global prevention even if an Apple event failed on a recovery path.
        if failures.isEmpty || mode == .normal {
            do { _ = try await command("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", mode == .background ? "1" : "0"]) }
            catch { failures.append("Power Protect 权限不可用：" + error.localizedDescription) }
        }
        if !failures.isEmpty { throw ModeError(failures.joined(separator: "\n")) }
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
