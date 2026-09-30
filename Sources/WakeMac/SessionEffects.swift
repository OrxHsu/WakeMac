// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 OrxHsu

import AppKit
import ApplicationServices
import IOKit.pwr_mgt
import Darwin

struct SessionEffectChoices: Equatable {
    var preventDisplaySleep = false
    var preventScreenSaver = false
    var moveCursor = false
    var driveAlive = false
    var mouseMovementIntervalSeconds: Double = 60
    var mouseOnlyWhenIdle = true
    var mouseIdleThresholdSeconds: Double = 60
    var mouseStopAfterIdleSeconds: Double? = nil
    var diskAccessIntervalSeconds: Double = 60
}

enum SessionEffectTiming {
    static func interval(_ value: Double) -> TimeInterval { value.isFinite ? min(max(value, 1), 86400) : 60 }
    static func due(last: Date?, now: Date, interval: Double) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= Self.interval(interval)
    }
    static func idleEnough(_ idleSeconds: TimeInterval, interval: Double) -> Bool {
        idleSeconds.isFinite && idleSeconds >= Self.interval(interval)
    }
}
struct SessionEffectReport: Equatable {
    var display = "未启用"
    var screenSaver = "允许屏保"
    var cursor = "未启用"
    var drives: [String: String] = [:]
}
@MainActor protocol SessionEffectManaging: AnyObject {
    func update(working: Bool, choices: SessionEffectChoices, directories: [URL], now: Date) -> SessionEffectReport
    func release()
}

/// Each effect belongs only to this controller. No global power, screensaver,
/// authentication preferences, or another application's assertions are touched.
@MainActor final class NativeSessionEffects: SessionEffectManaging {
    private var displayID: IOPMAssertionID?
    private var userActivityID: IOPMAssertionID?
    private var lastScreenPulse: Date?
    private var lastCursorPulse: Date?
    private var lastDrivePulse: Date?
    private var driveTask: Task<Void, Never>?
    private var driveReports: [String: String] = [:]
    private var generation = UUID()
    private let driveWorker = SessionDriveWorker()
    private var lockObserver: NSObjectProtocol?
    private var forcedLocked = false
    // Unavailable/off-console session information is treated as locked. This read cannot unlock a session.
    var unlockedProvider: () -> Bool = NativeSessionEffects.isUnlocked
    var screenSaverActiveProvider: () -> Bool? = NativeSessionEffects.isScreenSaverActive
    var accessibilityProvider: () -> Bool = AXIsProcessTrusted
    var idleSecondsProvider: () -> TimeInterval = { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!) }
    // Injection never prompts for a permission or emits a real pointer event in tests.
    var cursorMovement: (() -> Bool)?
    var drivePulse: (([URL]) async -> [String: String])?

    init() {
        lockObserver = DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.forcedLocked = true; self?.releaseInteractiveEffects() }
        }
        // Unlock is accepted only after the read-only session probe also confirms it.
        unlockObserver = DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.forcedLocked = false }
        }
    }
    private var unlockObserver: NSObjectProtocol?

    func update(working: Bool, choices: SessionEffectChoices, directories: [URL], now: Date) -> SessionEffectReport {
        guard working else { release(); return SessionEffectReport() }
        var report = SessionEffectReport()
        let unlocked = !forcedLocked && unlockedProvider()
        if !unlocked { releaseInteractiveEffects() }
        if choices.preventDisplaySleep && unlocked {
            report.display = acquireDisplay() ? "会话期间阻止显示器闲时休眠" : "无法建立显示器保活断言"
        } else {
            releaseAssertion(&displayID)
            report.display = choices.preventDisplaySleep ? "已锁定或状态未知，显示器保活已暂停" : "允许显示器休眠"
        }
        if choices.preventScreenSaver && unlocked {
            if lastScreenPulse == nil || now.timeIntervalSince(lastScreenPulse!) >= 10 {
                var id = userActivityID ?? 0
                let result = IOPMAssertionDeclareUserActivity("WorkModes session screensaver pause" as CFString, kIOPMUserActiveLocal, &id)
                if result == kIOReturnSuccess { userActivityID = id; lastScreenPulse = now }
                else { releaseAssertion(&userActivityID) }
            }
            report.screenSaver = userActivityID == nil ? "无法声明用户活动" : "延后闲时屏保与显示器休眠；锁定后暂停"
        } else {
            releaseAssertion(&userActivityID); lastScreenPulse = nil
            report.screenSaver = choices.preventScreenSaver ? "已锁定或状态未知，屏保控制已暂停" : "允许屏保"
        }
        if choices.moveCursor {
            if !unlocked { report.cursor = "已锁定或状态未知，鼠标移动已暂停" }
            else if screenSaverActiveProvider() != false { report.cursor = "屏保正在运行或状态未知，鼠标移动已暂停" }
            else if !accessibilityProvider() { report.cursor = "需要在系统设置中授予辅助功能权限" }
            else if let stopAfter = choices.mouseStopAfterIdleSeconds, !Self.idleBelowStop(idleSecondsProvider(), stopAfter: stopAfter) {
                report.cursor = "达到停止移动的闲置时长，鼠标移动已暂停"
            } else if choices.mouseOnlyWhenIdle && !SessionEffectTiming.idleEnough(idleSecondsProvider(), interval: choices.mouseIdleThresholdSeconds) {
                report.cursor = "等待连续闲置达到所设起始时长"
            } else if SessionEffectTiming.due(last: lastCursorPulse, now: now, interval: choices.mouseMovementIntervalSeconds) {
                // Recheck the console session directly before the effect, including injected tests.
                let moved = !forcedLocked && unlockedProvider() && (cursorMovement?() ?? nudgeCursor())
                report.cursor = moved ? "按所设间隔微移指针，保留系统闲置计时" : "无法移动鼠标"
                lastCursorPulse = now
            } else { report.cursor = "等待下一次鼠标移动间隔" }
        } else { lastCursorPulse = nil }
        if choices.driveAlive {
            let selected = Set(directories.map(\.path))
            driveReports = driveReports.filter { selected.contains($0.key) }
            for directory in directories where driveReports[directory.path] == nil { driveReports[directory.path] = "等待本地磁盘核验" }
            if driveTask == nil, SessionEffectTiming.due(last: lastDrivePulse, now: now, interval: choices.diskAccessIntervalSeconds) {
                lastDrivePulse = now
                let token = generation, worker = driveWorker, pulse = drivePulse
                driveTask = Task { [weak self] in
                    let results: [String: String]
                    if let pulse { results = await pulse(directories) }
                    else { results = await worker.pulse(directories: directories) }
                    guard !Task.isCancelled, let self, self.generation == token else { return }
                    self.driveReports = results; self.driveTask = nil
                }
            }
            report.drives = driveReports
        } else {
            cancelDrive(); lastDrivePulse = nil; driveReports = [:]
        }
        return report
    }
    func release() {
        releaseInteractiveEffects(); cancelDrive(); driveReports = [:]; lastDrivePulse = nil
    }
    private func releaseInteractiveEffects() {
        releaseAssertion(&displayID); releaseAssertion(&userActivityID)
        lastScreenPulse = nil; lastCursorPulse = nil
    }
    private func cancelDrive() { generation = UUID(); driveTask?.cancel(); driveTask = nil }
    private func acquireDisplay() -> Bool {
        if let id = displayID {
            if let props = IOPMAssertionCopyProperties(id)?.takeRetainedValue() as? [String: Any],
               (props[kIOPMAssertionLevelKey] as? NSNumber)?.uint32Value == UInt32(kIOPMAssertionLevelOn) { return true }
            releaseAssertion(&displayID)
        }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "WorkModes session display" as CFString, &id)
        guard result == kIOReturnSuccess else { return false }
        displayID = id
        guard let props = IOPMAssertionCopyProperties(id)?.takeRetainedValue() as? [String: Any],
              (props[kIOPMAssertionLevelKey] as? NSNumber)?.uint32Value == UInt32(kIOPMAssertionLevelOn) else {
            releaseAssertion(&displayID); return false
        }
        return true
    }
    private func releaseAssertion(_ id: inout IOPMAssertionID?) {
        guard let value = id else { return }
        let result = IOPMAssertionRelease(value)
        // Keep ownership after an unexpected failure so the next tick/shutdown retries.
        if result == kIOReturnSuccess || result == kIOReturnNotFound { id = nil }
    }
    private func nudgeCursor() -> Bool {
        // Recheck immediately before sending the event, even after update's first check.
        guard !forcedLocked, unlockedProvider(), AXIsProcessTrusted(),
              let probe = CGEvent(source: nil) else { return false }
        let current = probe.location
        var shifted = CGPoint(x: current.x + 1, y: current.y)
        if !NSScreen.screens.contains(where: { NSMouseInRect(shifted, $0.frame, false) }) { shifted.x = current.x - 1 }
        // Warp moves the pointer without posting an input event. It therefore
        // preserves the user's real idle time for start/stop thresholds and does
        // not imitate typing, dismiss a saver, or reset the lock idle clock.
        guard CGWarpMouseCursorPosition(shifted) == .success else { return false }
        // Restore only if the pointer still occupies our own shifted position;
        // physical movement between the two calls must retain ownership.
        if !forcedLocked, unlockedProvider(), CGEvent(source: nil)?.location == shifted {
            return CGWarpMouseCursorPosition(current) == .success
        }
        return true
    }
    private static func idleBelowStop(_ idle: Double, stopAfter: Double) -> Bool {
        idle.isFinite && idle >= 0 && idle < SessionEffectTiming.interval(stopAfter)
    }
    nonisolated static func isScreenSaverActive() -> Bool? {
        // The engine's presence is conservative: if it remains resident, mouse
        // movement stays paused. Unsupported/incomplete inventories stay unknown.
        let path = "/System/Library/CoreServices/ScreenSaverEngine.app/Contents/MacOS/ScreenSaverEngine"
        let canonical = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        let snapshot = ProcessDiscovery.snapshot()
        if snapshot.processes.contains(where: { $0.executablePath == canonical }) { return true }
        return snapshot.isComplete ? false : nil
    }
    nonisolated static func isUnlocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              session[kCGSessionOnConsoleKey as String] as? Bool == true,
              session[kCGSessionLoginDoneKey as String] as? Bool == true else { return false }
        // macOS omits this flag for a normal unlocked console session.
        return session["CGSSessionScreenIsLocked"] as? Bool != true
    }
    static func requestAccessibility() {
        // Invoked only by the user pressing the permission button, never by tick/start/tests.
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
    deinit {
        if let lockObserver { DistributedNotificationCenter.default().removeObserver(lockObserver) }
        if let unlockObserver { DistributedNotificationCenter.default().removeObserver(unlockObserver) }
        driveTask?.cancel()
        if let displayID { IOPMAssertionRelease(displayID) }
        if let userActivityID { IOPMAssertionRelease(userActivityID) }
    }
}

/// Disk I/O is serialized off the main actor. Each marker exists only within one
/// bounded operation; O_EXCL/O_NOFOLLOW and unlinkat prevent touching another file.
actor SessionDriveWorker {
    func pulse(directories: [URL]) -> [String: String] {
        var reports: [String: String] = [:]
        for directory in directories {
            guard !Task.isCancelled else { break }
            reports[directory.path] = Self.pulseDirectory(directory)
        }
        return reports
    }
    nonisolated static func pulseDirectory(_ directory: URL) -> String {
        do {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .volumeIsLocalKey, .volumeIsReadOnlyKey, .volumeIsRemovableKey])
            guard values.isDirectory == true else { return "目录不存在或已移除" }
            guard values.volumeIsLocal == true else { return "仅支持本地磁盘；网络或未知卷已跳过" }
            guard values.volumeIsReadOnly != true else { return "磁盘只读，已跳过" }
            let dirFD = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard dirFD >= 0 else { return "目录不可访问或磁盘已卸载" }
            defer { close(dirFD) }
            let name = ".workmodes-drivealive-" + UUID().uuidString
            let fd = openat(dirFD, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
            guard fd >= 0 else { return "无法写入所选目录" }
            defer { close(fd) }
            var byte: UInt8 = 0
            let synced = write(fd, &byte, 1) == 1 && fsync(fd) == 0
            // Remove only the inode we created, even if a directory entry changed
            // while the removable volume was being synchronized.
            var created = stat(), current = stat()
            let sameFile = fstat(fd, &created) == 0 && fstatat(dirFD, name, &current, AT_SYMLINK_NOFOLLOW) == 0
                && created.st_dev == current.st_dev && created.st_ino == current.st_ino
            let removed = sameFile && unlinkat(dirFD, name, 0) == 0
            guard removed else { return "临时文件未能清理，磁盘可能已移除；请检查目录" }
            guard synced else { return "写入或同步失败，磁盘可能已移除" }
            return values.volumeIsRemovable == true ? "已同步 · 可移除磁盘 · 不阻止手动弹出" : "已同步 · 本地磁盘"
        } catch { return "目录不可访问或磁盘已卸载" }
    }
}

/// Optional progress published through Foundation's public per-file channel.
/// This never reads Safari history, private plists, source URLs, or credentials.
typealias SessionProgressUnpublishingHandler = @Sendable () -> Void
typealias SessionProgressPublishingHandler = @Sendable (Progress) -> SessionProgressUnpublishingHandler?

@MainActor final class SessionDownloadProgressObserver {
    var addSubscriber: (URL, @escaping SessionProgressPublishingHandler) -> Any = { url, handler in
        Progress.addSubscriber(forFileURL: url, withPublishingHandler: handler)
    }
    var removeSubscriber: (Any) -> Void = { Progress.removeSubscriber($0) }
    private var subscribers: [Any] = []
    private var observations: [ObjectIdentifier: [NSKeyValueObservation]] = [:]
    private var progresses: [ObjectIdentifier: Progress] = [:]
    private var expectedPaths = Set<String>()
    private var generation = UUID()
    private var update: ((Double?) -> Void)?

    func start(urls: [URL], update: @escaping (Double?) -> Void) {
        stop()
        self.update = update
        expectedPaths = Set(urls.map { $0.standardizedFileURL.resolvingSymlinksInPath().path })
        let token = generation
        for url in urls {
            let subscriber = addSubscriber(url) { [weak self] progress in
                MainActor.assumeIsolated {
                    guard let self, self.generation == token else { return nil }
                    self.accept(progress, token: token)
                    let id = ObjectIdentifier(progress)
                    return { [weak self] in
                        MainActor.assumeIsolated {
                            guard let self, self.generation == token else { return }
                            self.observations.removeValue(forKey: id)
                            self.progresses.removeValue(forKey: id)
                            self.report()
                        }
                    }
                }
            }
            subscribers.append(subscriber)
        }
    }
    func stop() {
        generation = UUID(); update = nil; observations = [:]; progresses = [:]; expectedPaths = []
        let owned = subscribers; subscribers = []
        for subscriber in owned { removeSubscriber(subscriber) }
    }
    private func accept(_ progress: Progress, token: UUID) {
        guard Self.matchesDownload(progress, expectedPaths: expectedPaths) else { return }
        let id = ObjectIdentifier(progress)
        progresses[id] = progress
        observations[id] = [
            progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.report()
                }
            },
            progress.observe(\.isCancelled, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.report()
                }
            }
        ]
    }
    private func report() {
        let values = progresses.values.compactMap { Self.percent($0, expectedPaths: expectedPaths) }
        // Multiple independent publishers for the same file cannot supply one
        // reliable percentage, so ambiguity remains unavailable.
        update?(values.count == 1 ? values.first : nil)
    }
    static func matchesDownload(_ progress: Progress, expectedPaths: Set<String>) -> Bool {
        guard progress.kind == .file, progress.fileOperationKind == .downloading, let url = progress.fileURL else { return false }
        return expectedPaths.contains(url.standardizedFileURL.resolvingSymlinksInPath().path)
    }
    static func percent(_ progress: Progress, expectedPaths: Set<String>) -> Double? {
        guard matchesDownload(progress, expectedPaths: expectedPaths),
              !progress.isIndeterminate, !progress.isCancelled, progress.totalUnitCount > 0,
              progress.fractionCompleted.isFinite, (0...1).contains(progress.fractionCompleted) else { return nil }
        return progress.fractionCompleted * 100
    }
    deinit { for subscriber in subscribers { removeSubscriber(subscriber) } }
}
