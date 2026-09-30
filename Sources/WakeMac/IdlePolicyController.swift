// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 OrxHsu

import AppKit
import CoreGraphics
import Combine
import WakeMacCore

@MainActor final class IdlePolicyController: ObservableObject {
    @Published var lockEnabled: Bool { didSet { save() } }
    @Published var lockMinutes: Double { didSet { save() } }
    @Published var screenSaverEnabled: Bool { didSet { save() } }
    @Published var screenSaverMinutes: Double { didSet { save() } }
    @Published private(set) var status = "仅在已核验的工作状态中生效。"
    var workingProvider: (() -> Bool)?
    var allowsScreenSaver: (() -> Bool)?
    var immediateAuthentication: () -> Bool = { true }
    var preflight: () async -> Bool = { true }
    var unlockedProvider: () -> Bool = NativeSessionEffects.isUnlocked
    var idleProvider: () -> Double = { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!) }
    var lockAction: () async throws -> Void = {
        _ = try await Task.detached { try CommandRunner.run("/usr/bin/pmset", ["displaysleepnow"], timeout: 5) }.value
    }
    var screenSaverAction: () async throws -> Void = {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
        guard FileManager.default.fileExists(atPath: url.path) else { throw ModeError("系统屏保程序不可用。") }
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
    private let preferences: UserDefaults
    private var lockFired = false, saverFired = false, running = false
    init(preferences: UserDefaults) {
        self.preferences = preferences
        lockEnabled = preferences.bool(forKey: "idle.lockEnabled")
        screenSaverEnabled = preferences.bool(forKey: "idle.saverEnabled")
        lockMinutes = preferences.object(forKey: "idle.lockMinutes") as? Double ?? 5
        screenSaverMinutes = preferences.object(forKey: "idle.saverMinutes") as? Double ?? 3
    }
    private func save() {
        preferences.set(lockEnabled, forKey: "idle.lockEnabled"); preferences.set(lockMinutes, forKey: "idle.lockMinutes")
        preferences.set(screenSaverEnabled, forKey: "idle.saverEnabled"); preferences.set(screenSaverMinutes, forKey: "idle.saverMinutes")
        lockFired = false; saverFired = false
    }
    func tick() async {
        guard !running else { return }
        guard workingProvider?() == true, unlockedProvider() else { lockFired = false; saverFired = false; return }
        let idle = idleProvider()
        guard idle.isFinite, idle >= 0, (1...240).contains(lockMinutes), (1...240).contains(screenSaverMinutes) else { status = "无法读取空闲时间或时长无效。"; return }
        if idle < lockMinutes * 60 { lockFired = false }
        if idle < screenSaverMinutes * 60 { saverFired = false }
        running = true; defer { running = false }
        do {
            if lockEnabled, immediateAuthentication(), idle >= lockMinutes * 60, !lockFired {
                guard await preflight(), immediateAuthentication(), workingProvider?() == true, unlockedProvider(), lockEnabled, idleProvider() >= lockMinutes * 60 else { return }
                // The caller requires verified immediate authentication. Sleep the display
                // instead of ever modifying the password requirement or unlocking.
                try await lockAction(); lockFired = true; status = "已请求熄屏锁定；系统保活会话仍继续。"
            } else if screenSaverEnabled, allowsScreenSaver?() != false, idle >= screenSaverMinutes * 60, !saverFired {
                guard await preflight(), workingProvider?() == true, unlockedProvider(), screenSaverEnabled, allowsScreenSaver?() != false, idleProvider() >= screenSaverMinutes * 60 else { return }
                try await screenSaverAction(); saverFired = true; status = "已启动系统屏保；密码要求跟随系统设置。"
            }
        } catch { status = error.localizedDescription }
    }
}
