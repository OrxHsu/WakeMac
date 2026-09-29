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
