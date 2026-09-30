import AppKit
import CoreGraphics
import IOKit
import WakeMacCore
import WakeMacPower
import os

actor MacBackend: ModeBackend {
    private let injectedCommand: (@Sendable (String, [String], TimeInterval) async throws -> String)?
    private let heartbeatInterval: UInt64
    init(command: (@Sendable (String, [String], TimeInterval) async throws -> String)? = nil,
         helper: any BackgroundLeaseClient = PowerHelperClient(), heartbeatInterval: UInt64 = 5_000_000_000) {
        injectedCommand = command; self.helper = helper; self.heartbeatInterval = max(1_000_000, heartbeatInterval)
    }
    private func command(_ path: String, _ args: [String], timeout: TimeInterval = 20) async throws -> String {
        if let injectedCommand { return try await injectedCommand(path, args, timeout) }
        return try await Task.detached(priority: .userInitiated) { try CommandRunner.run(path, args, timeout: timeout) }.value
    }
    private let assertion = NativeSleepAssertion()
    private let helper: any BackgroundLeaseClient
    private var backgroundRequested = false
    private var heartbeat: Task<Void, Never>?
    private var leaseGeneration: UInt64 = 0
    private var leaseFailure: String?
    private let leaseLogger = Logger(subsystem: "local.orx.WorkModes", category: "PowerLease")
    private func startHeartbeat() {
        let revision = leaseGeneration, interval = heartbeatInterval
        heartbeat = Task.detached(priority: .userInitiated) { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: interval) } catch { return }
                guard !Task.isCancelled, await self?.renewLease(generation: revision) == true else { return }
            }
        }
    }
    private func renewLease(generation revision: UInt64) async -> Bool {
        guard leaseGeneration == revision, backgroundRequested else { return false }
        let started = ProcessInfo.processInfo.systemUptime
        leaseLogger.debug("Lease renewal requested at \(started, privacy: .public)")
        do {
            try await helper.renew()
            guard leaseGeneration == revision, backgroundRequested else { return false }
            leaseLogger.debug("Lease renewal acknowledged at \(ProcessInfo.processInfo.systemUptime, privacy: .public)")
            return true
        } catch {
            guard leaseGeneration == revision, backgroundRequested else { return false }
            backgroundRequested = false
            let reason = error.localizedDescription
            do {
                try assertion.release()
                leaseFailure = "合盖会话已失效，已释放本应用的保活。\n" + reason
            } catch { leaseFailure = "合盖会话已失效；释放原生保活也失败：" + error.localizedDescription + "\n" + reason }
            leaseLogger.error("Lease renewal failed; native assertion released or failure retained")
            return false
        }
    }
    private func stopHeartbeat() async {
        leaseGeneration &+= 1
        let previous = heartbeat; heartbeat = nil
        previous?.cancel()
        // Drain an already-sent reply before changing the same XPC connection's
        // lease. A late failure must not invalidate a newly started session.
        await previous?.value
    }
    func snapshot() async throws -> Snapshot {
        if let leaseFailure { throw ModeError(leaseFailure) }
        let began = ProcessInfo.processInfo.systemUptime
        let power = try await command("/usr/bin/pmset", ["-g"])
        let policy = try await command("/usr/sbin/sysadminctl", ["-screenLock", "status"])
        if let leaseFailure { throw ModeError(leaseFailure) }
        let elapsed = ProcessInfo.processInfo.systemUptime - began
        if elapsed > 5 { leaseLogger.warning("Status readback took \(elapsed, privacy: .public) seconds; renewal runs independently") }
        return Snapshot(sleepDisabled: SystemParsing.sleepDisabled(power), lockPolicy: SystemParsing.lockPolicy(policy),
                        idleSleepPrevented: assertion.active, displaySleepAllowed: true, backgroundLeaseActive: backgroundRequested)
    }
    func configurePower(_ mode: WorkMode) async throws {
        await stopHeartbeat()
        leaseFailure = nil
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
            startHeartbeat()
        }
        let power = try await command("/usr/bin/pmset", ["-g"])
        if let leaseFailure { throw ModeError(leaseFailure) }
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
    deinit { heartbeat?.cancel() }
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
