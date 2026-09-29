import Foundation

public enum WorkMode: String, CaseIterable, Codable, Sendable { case background, desk, normal }
public enum LockPolicy: Equatable, Sendable { case off, immediate, delayed, unknown }
public struct Snapshot: Equatable, Sendable {
    public var sleepDisabled: Bool?
    public var lockPolicy: LockPolicy
    public var idleSleepPrevented: Bool?
    public var displaySleepAllowed: Bool?
    public var backgroundLeaseActive: Bool?
    public init(sleepDisabled: Bool?, lockPolicy: LockPolicy, idleSleepPrevented: Bool?, displaySleepAllowed: Bool?, backgroundLeaseActive: Bool?) {
        self.sleepDisabled = sleepDisabled; self.lockPolicy = lockPolicy
        self.idleSleepPrevented = idleSleepPrevented; self.displaySleepAllowed = displaySleepAllowed
        self.backgroundLeaseActive = backgroundLeaseActive
    }
    public func matches(_ mode: WorkMode) -> Bool {
        guard lockPolicy == .immediate, sleepDisabled == (mode == .background),
              backgroundLeaseActive == (mode == .background) else { return false }
        if mode == .normal { return idleSleepPrevented == false }
        return idleSleepPrevented == true && displaySleepAllowed == true
    }
    public var diagnostic: String {
        func state(_ b: Bool?) -> String { b.map { $0 ? "开" : "关" } ?? "未知" }
        return "全局防休眠 \(state(sleepDisabled))；原生保活 \(state(idleSleepPrevented))；本应用允许熄屏 \(state(displaySleepAllowed))；合盖服务会话 \(state(backgroundLeaseActive))；锁屏策略 \(lockPolicy)"
    }
}
public protocol ModeBackend {
    func snapshot() async throws -> Snapshot
    func configurePower(_ mode: WorkMode) async throws
    func requestLockPolicy(_ policy: LockPolicy) async
    func sleepNow() async throws
}
public enum TransitionResult: Equatable { case active(WorkMode), needsLockPolicy(WorkMode), sleepCancelled, failed(String) }
public actor ModeCoordinator {
    let backend: any ModeBackend
    private var busy = false
    public init(backend: any ModeBackend) { self.backend = backend }
    public func select(_ mode: WorkMode) async -> TransitionResult { await transition(mode, sleep: false) }
    public func sleep(shouldProceed: @escaping @Sendable () async -> Bool = { true }) async -> TransitionResult {
        await transition(.normal, sleep: true, shouldProceed: shouldProceed)
    }
    private func transition(_ mode: WorkMode, sleep: Bool, shouldProceed: @escaping @Sendable () async -> Bool = { true }) async -> TransitionResult {
        guard !busy else { return .failed("正在切换模式，请稍候。") }
        busy = true
        defer { busy = false }
        do {
            // Always release our inhibitors before a Normal-mode authentication handoff.
            if mode == .normal { try await backend.configurePower(.normal) }
            let before = try await backend.snapshot()
            let desired: LockPolicy = .immediate
            guard before.lockPolicy == desired else {
                await backend.requestLockPolicy(desired)
                return .needsLockPolicy(mode)
            }
            if mode != .normal { try await backend.configurePower(mode) }
            let after = try await backend.snapshot()
            guard after.matches(mode) else { throw ModeError("系统回读与所选模式不一致，未标记为成功。\n" + after.diagnostic) }
            if sleep {
                guard await shouldProceed() else { return .sleepCancelled }
                try await backend.sleepNow()
            }
            return .active(mode)
        } catch {
            var message = error.localizedDescription
            if mode != .normal {
                do { try await backend.configurePower(.normal) }
                catch { message += "\n恢复休眠也失败：" + error.localizedDescription }
            }
            return .failed(message)
        }
    }
}
public struct ModeError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
