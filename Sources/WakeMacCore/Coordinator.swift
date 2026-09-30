// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 OrxHsu

import Foundation

public enum WorkMode: String, CaseIterable, Codable, Sendable { case background, desk, normal }
public enum LockPolicy: Equatable, Sendable { case off, immediate, delayed, unknown }
public enum LockRequirement: Sendable {
    case immediate, system
    public func accepts(_ policy: LockPolicy) -> Bool {
        policy != .unknown && (self == .system || policy == .immediate)
    }
}
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
    public func matches(_ mode: WorkMode, lockRequirement: LockRequirement = .immediate) -> Bool {
        guard lockRequirement.accepts(lockPolicy), sleepDisabled == (mode == .background),
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
    public func select(_ mode: WorkMode, lockRequirement: LockRequirement = .immediate) async -> TransitionResult { await transition(mode, sleep: false, lockRequirement: lockRequirement) }
    public func sleep(lockRequirement: LockRequirement = .immediate, shouldProceed: @escaping @Sendable () async -> Bool = { true }) async -> TransitionResult {
        await transition(.normal, sleep: true, lockRequirement: lockRequirement, shouldProceed: shouldProceed)
    }
    private func transition(_ mode: WorkMode, sleep: Bool, lockRequirement: LockRequirement, shouldProceed: @escaping @Sendable () async -> Bool = { true }) async -> TransitionResult {
        guard !busy else { return .failed("正在切换模式，请稍候。") }
        busy = true
        defer { busy = false }
        do {
            // Always release our inhibitors before a Normal-mode authentication handoff.
            if mode == .normal { try await backend.configurePower(.normal) }
            let before = try await backend.snapshot()
            if !lockRequirement.accepts(before.lockPolicy) {
                guard lockRequirement == .immediate else { throw ModeError("无法核验系统锁屏设置；未启用工作模式。") }
                await backend.requestLockPolicy(.immediate)
                return .needsLockPolicy(mode)
            }
            if mode != .normal { try await backend.configurePower(mode) }
            let after = try await backend.snapshot()
            guard after.matches(mode, lockRequirement: lockRequirement) else { throw ModeError("系统回读与所选模式不一致，未标记为成功。\n" + after.diagnostic) }
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
