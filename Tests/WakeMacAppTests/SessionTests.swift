import XCTest
@testable import WakeMac
import WakeMacCore

@MainActor private final class TestSessionEffects: SessionEffectManaging {
    var updates = 0
    var releases = 0
    var active = false
    func update(working: Bool, choices: SessionEffectChoices, directories: [URL], now: Date) -> SessionEffectReport {
        updates += 1; active = working
        return SessionEffectReport(display: "test", screenSaver: "test", cursor: "test", drives: [:])
    }
    func release() { releases += 1; active = false }
}

@MainActor final class SessionTests: XCTestCase {
    private func controller(_ effects: TestSessionEffects) -> SessionController {
        SessionController(preferences: UserDefaults(suiteName: "SessionTests." + UUID().uuidString)!, effects: effects)
    }
    func testProcessSessionWaitsThroughUnknownAndEndsSelectedIdentityOnce() async {
        let e = TestSessionEffects(), c = controller(e)
        let identity = NativeProcessIdentity(pid: 123, startedSeconds: 100, startedMicroseconds: 2)
        var presence: NativeProcessReading = .running, endings = 0
        c.endCondition = .process; c.selectedProcess = .init(identity: identity, name: "worker", executablePath: "/tmp/worker")
        c.processProbe = { value in XCTAssertEqual(value, identity); return presence }
        c.workingProvider = { true }; c.onBegin = { _ in true }; c.onEnd = { XCTAssertFalse(e.active); endings += 1 }
        await c.start(); XCTAssertTrue(c.isActive)
        presence = .unavailable; await c.tick(now: Date()); XCTAssertTrue(c.isActive); XCTAssertEqual(endings, 0)
        presence = .exited; await c.tick(now: Date()); await c.tick(now: Date())
        XCTAssertFalse(c.isActive); XCTAssertEqual(endings, 1)
    }
    func testExtendPreservesExistingDeadlineAndRejectsExpiredOrUntimedPlans() async {
        let e = TestSessionEffects(), c = controller(e), now = Date()
        c.workingProvider = { true }; c.onBegin = { _ in true }
        var extended: [Double] = []
        c.onExtended = { extended.append($0) }
        XCTAssertFalse(c.extend(minutes: 15, now: now)); XCTAssertTrue(extended.isEmpty)
        c.endCondition = .duration; c.durationMinutes = 1; await c.start(now: now)
        XCTAssertTrue(c.extend(minutes: 15, now: now.addingTimeInterval(10)))
        XCTAssertEqual(c.deadline, now.addingTimeInterval(960))
        XCTAssertFalse(c.extend(minutes: .nan, now: now)); XCTAssertFalse(c.extend(minutes: 10081, now: now))
        XCTAssertEqual(c.deadline, now.addingTimeInterval(960))
        await c.tick(now: now.addingTimeInterval(60)); XCTAssertTrue(c.isActive)
        XCTAssertFalse(c.extend(minutes: 1, now: now.addingTimeInterval(960)))
        c.manualModeChanged(); c.endCondition = .untilDate; c.endDate = now.addingTimeInterval(120)
        await c.start(now: now); XCTAssertTrue(c.extend(minutes: 1, now: now))
        XCTAssertEqual(c.deadline, now.addingTimeInterval(180)); XCTAssertEqual(c.endDate, c.deadline)
        c.manualModeChanged(); c.endCondition = .indefinite; await c.start(now: now)
        XCTAssertFalse(c.extend(minutes: 15, now: now))
        XCTAssertEqual(extended, [15, 1])
    }
    func testSavedSessionConfigurationNeverReplaysActiveStateAndIntervalsDoNotRecurse() async {
        let prefs = UserDefaults(suiteName: "SessionTests." + UUID().uuidString)!
        let c = SessionController(preferences: prefs, effects: TestSessionEffects())
        c.endCondition = .duration; c.durationMinutes = 45
        c.downloadStabilitySeconds = 120; c.downloadStabilitySeconds = 120
        c.mouseMovementIntervalSeconds = 5; c.mouseIdleThresholdSeconds = 60; c.mouseOnlyWhenIdle = false
        c.mouseStopAfterIdleSeconds = 1200; c.diskAccessIntervalSeconds = 15
        c.screenSaverExceptionBundleIDs = ["com.test.editor"]
        c.workingProvider = { true }; c.onBegin = { _ in true }; await c.start()
        let restored = SessionController(preferences: prefs, effects: TestSessionEffects())
        XCTAssertFalse(restored.isActive); XCTAssertNil(restored.deadline); XCTAssertNil(restored.selectedProcess)
        XCTAssertEqual(restored.endCondition, .duration); XCTAssertEqual(restored.durationMinutes, 45)
        XCTAssertEqual(restored.downloadStabilitySeconds, 120); XCTAssertEqual(restored.mouseMovementIntervalSeconds, 5)
        XCTAssertEqual(restored.mouseIdleThresholdSeconds, 60); XCTAssertFalse(restored.mouseOnlyWhenIdle)
        XCTAssertEqual(restored.mouseStopAfterIdleSeconds, 1200); XCTAssertEqual(restored.diskAccessIntervalSeconds, 15)
        XCTAssertEqual(restored.screenSaverExceptionBundleIDs, ["com.test.editor"])
        c.diskAccessIntervalSeconds = 0; XCTAssertEqual(c.diskAccessIntervalSeconds, 1)
        c.mouseIdleThresholdSeconds = .infinity; XCTAssertEqual(c.mouseIdleThresholdSeconds, 60)
        c.mouseStopAfterIdleSeconds = .nan; XCTAssertNil(c.mouseStopAfterIdleSeconds)
    }
    func testRuntimeOverridesAndSaverExceptionsKeepSavedPreventionIndependent() {
        let e = TestSessionEffects(), c = controller(e)
        c.preventDisplaySleep = false; c.preventScreenSaver = true
        c.setDisplayPrevention(true); XCTAssertTrue(c.choices.preventDisplaySleep); XCTAssertFalse(c.preventDisplaySleep)
        c.setScreenSaverPrevention(false); XCTAssertFalse(c.effectivePreventScreenSaver); XCTAssertTrue(c.preventScreenSaver)
        c.effectOverrides = nil; XCTAssertFalse(c.effectivePreventDisplaySleep); XCTAssertTrue(c.effectivePreventScreenSaver)
        var reading: SessionApplicationReading = .running([1])
        var working = true
        c.workingProvider = { working }; c.screenSaverExceptionBundleIDs = ["com.test.editor"]
        c.screenSaverExceptionProbe = { _ in reading }
        XCTAssertTrue(c.screenSaverExceptionActive); XCTAssertTrue(c.effectivePreventScreenSaver)
        reading = .absent; XCTAssertFalse(c.screenSaverExceptionActive)
        reading = .unavailable; XCTAssertTrue(c.screenSaverExceptionActive)
        working = false; XCTAssertFalse(c.screenSaverExceptionActive)
    }
    func testConfiguredDownloadStabilityPeriodRequiresActualProgress() async {
        let e = TestSessionEffects(), c = controller(e), now = Date()
        var bytes: Int64 = 100
        c.endCondition = .download; c.downloadURL = URL(fileURLWithPath: "/tmp/test.bin"); c.downloadStabilitySeconds = 120
        c.downloadProbe = { _ in .file(.init(bytes: bytes, modified: now, identity: 1)) }
        c.workingProvider = { true }; c.onBegin = { _ in true }
        await c.start(now: now); await c.tick(now: now.addingTimeInterval(500)); XCTAssertTrue(c.isActive)
        bytes = 200; await c.tick(now: now.addingTimeInterval(501))
        await c.tick(now: now.addingTimeInterval(620)); XCTAssertTrue(c.isActive)
        await c.tick(now: now.addingTimeInterval(621)); XCTAssertFalse(c.isActive)
    }
    func testDurationEndsOnceAndReleasesEffectsBeforeEndCallback() async {
        let e = TestSessionEffects(), c = controller(e), now = Date()
        var working = false, endings = 0
        c.workingProvider = { working }
        c.onBegin = { _ in working = true; return true }
        c.onEnd = { XCTAssertFalse(e.active); endings += 1; working = false }
        c.endCondition = .duration; c.durationMinutes = 1
        await c.start(now: now)
        XCTAssertTrue(c.isActive); XCTAssertTrue(e.active)
        await c.tick(now: now.addingTimeInterval(60))
        await c.tick(now: now.addingTimeInterval(61))
        XCTAssertFalse(c.isActive); XCTAssertEqual(endings, 1); XCTAssertFalse(e.active)
    }
    func testFailedStartAndLostVerificationReleaseEffects() async {
        let e = TestSessionEffects(), c = controller(e)
        c.workingProvider = { true }; c.onBegin = { _ in false }
        await c.start(); XCTAssertFalse(c.isActive); XCTAssertFalse(e.active)
        var working = true
        c.workingProvider = { working }; c.onBegin = { _ in true }
        await c.start(); XCTAssertTrue(e.active)
        working = false; await c.tick(now: Date())
        XCTAssertFalse(c.isActive); XCTAssertFalse(e.active)
    }
    func testLostVerificationEndsOwnedWorkOnceAndIgnoresLateStatusAfterManualChange() async {
        let e = TestSessionEffects(), c = controller(e)
        var working = true, backendLease = false, endings = 0
        var gate: CheckedContinuation<Void, Never>?
        c.workingProvider = { working }
        c.onBegin = { _ in backendLease = true; return true }
        c.onEnd = {
            XCTAssertFalse(e.active)
            endings += 1; backendLease = false
            await withCheckedContinuation { gate = $0 }
        }
        await c.start(); XCTAssertTrue(backendLease)
        working = false
        let pending = Task { await c.tick(now: Date()) }
        for _ in 0..<100 where gate == nil { await Task.yield() }
        XCTAssertEqual(endings, 1); XCTAssertFalse(backendLease); XCTAssertFalse(c.isActive)
        await c.tick(now: Date()); XCTAssertEqual(endings, 1)
        c.manualModeChanged(); let manualStatus = c.status
        gate?.resume(); await pending.value
        XCTAssertEqual(c.status, manualStatus); XCTAssertEqual(endings, 1)
    }
    func testManualTransitionCancelsPlanBeforeTemporaryUnverifiedSnapshot() async {
        let e = TestSessionEffects(), c = controller(e)
        var working = true, endings = 0
        c.workingProvider = { working }; c.onBegin = { _ in true }; c.onEnd = { endings += 1 }
        await c.start()
        c.manualModeChanged(); working = false
        await c.tick(now: Date()); XCTAssertEqual(endings, 0); XCTAssertFalse(e.active)
        working = true; await c.tick(now: Date())
        XCTAssertEqual(endings, 0); XCTAssertTrue(e.active); XCTAssertFalse(c.isActive)
    }
    func testDurationRequiresOneMinuteThroughSevenDays() async {
        let e = TestSessionEffects(), c = controller(e)
        var beginnings = 0
        c.workingProvider = { true }; c.onBegin = { _ in beginnings += 1; return true }
        c.endCondition = .duration
        for invalid in [0.5, 10081, Double.infinity, Double.nan] {
            c.durationMinutes = invalid; await c.start(); XCTAssertFalse(c.isActive)
        }
        XCTAssertEqual(beginnings, 0)
        c.durationMinutes = 1; await c.start(); XCTAssertTrue(c.isActive); c.manualModeChanged()
        c.durationMinutes = 10080; await c.start(); XCTAssertTrue(c.isActive); XCTAssertEqual(beginnings, 2)
    }
    func testLateBeginCannotRestoreCancelledSessionOrEffects() async {
        let e = TestSessionEffects(), c = controller(e)
        var gate: CheckedContinuation<Bool, Never>?
        c.workingProvider = { true }
        c.onBegin = { _ in await withCheckedContinuation { gate = $0 } }
        let pending = Task { await c.start() }
        while gate == nil { await Task.yield() }
        c.manualModeChanged()
        gate?.resume(returning: true)
        await pending.value
        XCTAssertFalse(c.isActive); XCTAssertFalse(e.active); XCTAssertFalse(c.isStarting)
    }
    func testUntilDateEndsAtChosenDateAndRejectsPastDate() async {
        let e = TestSessionEffects(), c = controller(e), now = Date()
        var endings = 0
        c.workingProvider = { true }; c.onBegin = { _ in true }; c.onEnd = { endings += 1 }
        c.endCondition = .untilDate; c.endDate = now.addingTimeInterval(-1)
        await c.start(now: now); XCTAssertFalse(c.isActive)
        c.endDate = now.addingTimeInterval(30)
        await c.start(now: now); await c.tick(now: now.addingTimeInterval(29)); XCTAssertTrue(c.isActive)
        await c.tick(now: now.addingTimeInterval(30)); XCTAssertFalse(c.isActive); XCTAssertEqual(endings, 1)
    }
    func testApplicationSelectionMustResolveRunningExactApplication() async {
        let e = TestSessionEffects(), c = controller(e)
        c.onBegin = { _ in XCTFail("must not begin unknown app"); return true }
        c.endCondition = .application; c.applicationURL = URL(fileURLWithPath: "/tmp/Missing.app")
        c.applicationProbe = { _ in .unavailable }
        await c.start(); XCTAssertFalse(c.isActive)
    }
    func testApplicationUnknownDoesNotPretendExitedButConfirmedExitEnds() async {
        let e = TestSessionEffects(), c = controller(e), app = URL(fileURLWithPath: "/tmp/Test.app")
        var probe: SessionApplicationReading = .running([123])
        var endings = 0
        c.applicationProbe = { _ in probe }; c.applicationURL = app; c.endCondition = .application
        c.workingProvider = { true }; c.onBegin = { _ in true }; c.onEnd = { endings += 1 }
        await c.start(); probe = .unavailable; await c.tick(now: Date())
        XCTAssertTrue(c.isActive); XCTAssertEqual(endings, 0)
        probe = .absent; await c.tick(now: Date())
        XCTAssertFalse(c.isActive); XCTAssertEqual(endings, 1)
    }
    func testIdleFileCannotBeCalledCompletedAndProgressNeedsStability() async {
        let e = TestSessionEffects(), c = controller(e), now = Date()
        var file = SessionDownloadReading.file(SessionFileStamp(bytes: 100, modified: now, identity: 1))
        var endings = 0
        c.endCondition = .download; c.downloadURL = URL(fileURLWithPath: "/tmp/test.bin")
        c.downloadProbe = { _ in file }; c.workingProvider = { true }; c.onBegin = { _ in true }; c.onEnd = { endings += 1 }
        await c.start(now: now)
        await c.tick(now: now.addingTimeInterval(120)); XCTAssertTrue(c.isActive)
        file = .file(SessionFileStamp(bytes: 200, modified: now.addingTimeInterval(121), identity: 1))
        await c.tick(now: now.addingTimeInterval(121))
        file = .unavailable
        await c.tick(now: now.addingTimeInterval(160)); XCTAssertTrue(c.isActive)
        file = .file(SessionFileStamp(bytes: 200, modified: now.addingTimeInterval(121), identity: 1))
        await c.tick(now: now.addingTimeInterval(161)); XCTAssertTrue(c.isActive)
        await c.tick(now: now.addingTimeInterval(192)); XCTAssertFalse(c.isActive); XCTAssertEqual(endings, 1)
    }
    func testPartialDownloadNeverEndsWhileTemporaryExtensionRemains() async {
        let e = TestSessionEffects(), c = controller(e), now = Date()
        let partial = URL(fileURLWithPath: "/tmp/test.bin.crdownload")
        var size: Int64 = 10, final = false
        c.endCondition = .download; c.downloadURL = partial
        c.downloadProbe = { url in
            if url == partial { return final ? .missing : .file(SessionFileStamp(bytes: size, modified: now, identity: 1)) }
            return final ? .file(SessionFileStamp(bytes: size, modified: now, identity: 1)) : .missing
        }
        c.workingProvider = { true }; c.onBegin = { _ in true }; c.onEnd = {}
        await c.start(now: now); size = 20
        await c.tick(now: now.addingTimeInterval(1)); await c.tick(now: now.addingTimeInterval(60))
        XCTAssertTrue(c.isActive)
        final = true; await c.tick(now: now.addingTimeInterval(61)); await c.tick(now: now.addingTimeInterval(92))
        XCTAssertFalse(c.isActive)
    }
    func testCancelledPartialCannotCompleteFromAnOldDestinationFile() async {
        let e = TestSessionEffects(), c = controller(e), now = Date()
        let partial = URL(fileURLWithPath: "/tmp/test.bin.crdownload")
        var size: Int64 = 10, removed = false
        c.endCondition = .download; c.downloadURL = partial
        c.downloadProbe = { url in
            if url == partial { return removed ? .missing : .file(SessionFileStamp(bytes: size, modified: now, identity: 1)) }
            return .file(SessionFileStamp(bytes: 500, modified: now.addingTimeInterval(-500), identity: 2))
        }
        c.workingProvider = { true }; c.onBegin = { _ in true }; c.onEnd = { XCTFail("old destination is not completed download") }
        await c.start(now: now); size = 20; await c.tick(now: now.addingTimeInterval(1))
        removed = true; await c.tick(now: now.addingTimeInterval(2)); await c.tick(now: now.addingTimeInterval(120))
        XCTAssertTrue(c.isActive)
    }
    func testEffectsFollowVerifiedManualWorkWithoutAStartedSession() async {
        let e = TestSessionEffects(), c = controller(e)
        var working = true
        c.workingProvider = { working }
        await c.tick(now: Date())
        XCTAssertFalse(c.isActive); XCTAssertTrue(e.active)
        working = false; await c.tick(now: Date())
        XCTAssertFalse(e.active)
    }
    func testManualChangeAndShutdownDoNotInvokeEndOrReplaySession() async {
        let e = TestSessionEffects(), c = controller(e)
        var endings = 0
        c.workingProvider = { true }; c.onBegin = { _ in true }; c.onEnd = { endings += 1 }
        await c.start(); c.manualModeChanged(); XCTAssertFalse(e.active); await c.tick(now: Date()); XCTAssertEqual(endings, 0)
        await c.start(); c.shutdown(); XCTAssertFalse(e.active); XCTAssertEqual(endings, 0)
        await c.start(); XCTAssertFalse(c.isActive)
    }
}

@MainActor final class SessionNativeEffectsTests: XCTestCase {
    func testProgressSubscriptionHandlesInitiallyUnknownFractionAndDropsLateUpdatesAfterStop() async {
        let observer = SessionDownloadProgressObserver()
        let file = URL(fileURLWithPath: "/tmp/progress-test.bin")
        var handler: SessionProgressPublishingHandler?, removals = 0
        observer.addSubscriber = { url, received in XCTAssertEqual(url, file); handler = received; return NSObject() }
        observer.removeSubscriber = { _ in removals += 1 }
        let known = expectation(description: "native published fraction becomes available")
        let cancelled = expectation(description: "cancelled publisher no longer supplies a percentage")
        var values: [Double?] = [], fulfilled = false, cancellationRequested = false, cancellationReported = false
        observer.start(urls: [file]) { value in
            values.append(value)
            if value == 25 && !fulfilled { fulfilled = true; known.fulfill() }
            if cancellationRequested && value == nil && !cancellationReported { cancellationReported = true; cancelled.fulfill() }
        }
        let progress = Progress(totalUnitCount: -1)
        progress.kind = .file; progress.fileOperationKind = .downloading; progress.fileURL = file
        let unpublish = handler?(progress)
        progress.totalUnitCount = 100; progress.completedUnitCount = 25
        await fulfillment(of: [known], timeout: 1)
        XCTAssertEqual(values.last ?? nil, 25)
        cancellationRequested = true; progress.cancel()
        await fulfillment(of: [cancelled], timeout: 1)
        XCTAssertNil(values.last ?? nil)
        observer.stop(); XCTAssertEqual(removals, 1)
        let count = values.count
        progress.completedUnitCount = 75; unpublish?()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(values.count, count)
    }
    func testDownloadPercentageRequiresExactPublishedDownloadingMetadata() {
        let file = URL(fileURLWithPath: "/tmp/progress-test.bin")
        let expected: Set<String> = [file.path]
        let progress = Progress(totalUnitCount: 100)
        progress.kind = .file; progress.fileOperationKind = .downloading; progress.fileURL = file; progress.completedUnitCount = 25
        XCTAssertEqual(SessionDownloadProgressObserver.percent(progress, expectedPaths: expected), 25)
        progress.fileURL = URL(fileURLWithPath: "/tmp/other-file.bin")
        XCTAssertNil(SessionDownloadProgressObserver.percent(progress, expectedPaths: expected))
        progress.fileURL = file; progress.fileOperationKind = .copying
        XCTAssertNil(SessionDownloadProgressObserver.percent(progress, expectedPaths: expected))
        progress.fileOperationKind = .downloading; progress.totalUnitCount = -1
        XCTAssertTrue(SessionDownloadProgressObserver.matchesDownload(progress, expectedPaths: expected))
        XCTAssertNil(SessionDownloadProgressObserver.percent(progress, expectedPaths: expected))
        progress.totalUnitCount = 100; progress.cancel()
        XCTAssertNil(SessionDownloadProgressObserver.percent(progress, expectedPaths: expected))
    }
    func testMouseIntervalIdleStartStopAndSaverPauseWithoutSendingEvents() {
        let effects = NativeSessionEffects(), now = Date()
        var idle = 50.0, moves = 0
        var saver: Bool? = false
        effects.unlockedProvider = { true }; effects.accessibilityProvider = { true }
        effects.screenSaverActiveProvider = { saver }; effects.idleSecondsProvider = { idle }
        effects.cursorMovement = { moves += 1; return true }
        var choices = SessionEffectChoices(moveCursor: true, mouseMovementIntervalSeconds: 5, mouseOnlyWhenIdle: true, mouseIdleThresholdSeconds: 60, mouseStopAfterIdleSeconds: 120)
        _ = effects.update(working: true, choices: choices, directories: [], now: now); XCTAssertEqual(moves, 0)
        idle = 60; _ = effects.update(working: true, choices: choices, directories: [], now: now); XCTAssertEqual(moves, 1)
        idle = 90; _ = effects.update(working: true, choices: choices, directories: [], now: now.addingTimeInterval(4)); XCTAssertEqual(moves, 1)
        _ = effects.update(working: true, choices: choices, directories: [], now: now.addingTimeInterval(5)); XCTAssertEqual(moves, 2)
        idle = 120; _ = effects.update(working: true, choices: choices, directories: [], now: now.addingTimeInterval(10)); XCTAssertEqual(moves, 2)
        idle = 90; saver = true; _ = effects.update(working: true, choices: choices, directories: [], now: now.addingTimeInterval(15)); XCTAssertEqual(moves, 2)
        saver = nil; _ = effects.update(working: true, choices: choices, directories: [], now: now.addingTimeInterval(20)); XCTAssertEqual(moves, 2)
        saver = false; choices.mouseOnlyWhenIdle = false; idle = 0
        _ = effects.update(working: true, choices: choices, directories: [], now: now.addingTimeInterval(25)); XCTAssertEqual(moves, 3)
        effects.unlockedProvider = { false }
        _ = effects.update(working: true, choices: choices, directories: [], now: now.addingTimeInterval(30)); XCTAssertEqual(moves, 3)
        effects.release()
    }
    func testDiskIntervalUsesConfiguredCadenceAndStopsWhenWorkUnverified() async {
        let effects = NativeSessionEffects(), now = Date()
        var pulses = 0
        effects.unlockedProvider = { false }
        effects.drivePulse = { _ in pulses += 1; return [:] }
        let choices = SessionEffectChoices(driveAlive: true, diskAccessIntervalSeconds: 10)
        _ = effects.update(working: true, choices: choices, directories: [], now: now)
        for _ in 0..<100 where pulses == 0 { await Task.yield() }
        XCTAssertEqual(pulses, 1)
        _ = effects.update(working: true, choices: choices, directories: [], now: now.addingTimeInterval(9)); await Task.yield(); XCTAssertEqual(pulses, 1)
        _ = effects.update(working: true, choices: choices, directories: [], now: now.addingTimeInterval(10))
        for _ in 0..<100 where pulses < 2 { await Task.yield() }
        XCTAssertEqual(pulses, 2)
        _ = effects.update(working: false, choices: choices, directories: [], now: now.addingTimeInterval(20)); await Task.yield(); XCTAssertEqual(pulses, 2)
    }
    func testDrivePulseOnlyLeavesTheUsersOriginalFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SessionDrive." + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: original)
        let report = SessionDriveWorker.pulseDirectory(dir)
        XCTAssertTrue(report.contains("已同步"), report)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["keep.txt"])
        XCTAssertEqual(try Data(contentsOf: original), Data("keep".utf8))
    }
    func testDrivePulseRejectsSymlinkDirectoryAndUnavailableDirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SessionDrive." + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let link = dir.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: dir)
        XCTAssertFalse(SessionDriveWorker.pulseDirectory(link).contains("已同步"))
        XCTAssertFalse(SessionDriveWorker.pulseDirectory(dir.appendingPathComponent("missing")).contains("已同步"))
    }
    func testUnverifiedOrLockedInteractiveEffectsDoNotAcquireAssertions() {
        let effects = NativeSessionEffects()
        effects.unlockedProvider = { false }
        let choices = SessionEffectChoices(preventDisplaySleep: true, preventScreenSaver: true, moveCursor: true, driveAlive: false)
        let report = effects.update(working: true, choices: choices, directories: [], now: Date())
        XCTAssertTrue(report.display.contains("暂停")); XCTAssertTrue(report.screenSaver.contains("暂停")); XCTAssertTrue(report.cursor.contains("暂停"))
        let idle = effects.update(working: false, choices: choices, directories: [], now: Date())
        XCTAssertEqual(idle, SessionEffectReport())
        effects.release()
    }
}
