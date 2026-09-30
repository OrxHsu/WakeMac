import XCTest
import WakeMacCore
@testable import WakeMac

private actor LockPreferenceBackend: ModeBackend {
    var mode = WorkMode.normal
    var lock: LockPolicy
    var requests = 0
    var sleeps = 0
    init(_ lock: LockPolicy) { self.lock = lock }
    func snapshot() -> Snapshot {
        Snapshot(sleepDisabled: mode == .background, lockPolicy: lock, idleSleepPrevented: mode != .normal, displaySleepAllowed: true, backgroundLeaseActive: mode == .background)
    }
    func configurePower(_ mode: WorkMode) { self.mode = mode }
    func requestLockPolicy(_ policy: LockPolicy) { requests += 1 }
    func sleepNow() { sleeps += 1 }
    func setLock(_ policy: LockPolicy) { lock = policy }
}

@MainActor private final class LockPreferenceEffects: SessionEffectManaging {
    var appliedDisplayPrevention = false
    var releases = 0
    func update(working: Bool, choices: SessionEffectChoices, directories: [URL], now: Date) -> SessionEffectReport {
        appliedDisplayPrevention = working && choices.preventDisplaySleep
        return SessionEffectReport()
    }
    func release() { appliedDisplayPrevention = false; releases += 1 }
}

@MainActor final class LockPreferenceTests: XCTestCase {
    private func model(_ backend: LockPreferenceBackend, followSystem: Bool) -> AppModel {
        let prefs = UserDefaults(suiteName: "WakeMac.LockPreference." + UUID().uuidString)!
        if followSystem { prefs.set(false, forKey: "RequireImmediateLock") }
        return AppModel(backend: backend, preferences: prefs, sessionEffects: LockPreferenceEffects())
    }
    func testFollowingKnownSystemPolicyAllowsAllModesAndSleepWithoutChangingAuthentication() async {
        for lock in [LockPolicy.off, .delayed, .immediate] {
            let b = LockPreferenceBackend(lock), m = model(b, followSystem: true)
            for mode in WorkMode.allCases {
                await m.choose(mode); XCTAssertEqual(m.active, mode); XCTAssertNil(m.pending); XCTAssertFalse(m.error)
                await m.refresh(); XCTAssertEqual(m.active, mode)
            }
            await m.choose(.normal, sleep: true)
            let requests = await b.requests, sleeps = await b.sleeps
            XCTAssertEqual(requests, 0); XCTAssertEqual(sleeps, 1)
        }
    }
    func testFollowSystemSessionStartsAndEndsWithDisplayActionsAppliedToCurrentSession() async throws {
        let b = LockPreferenceBackend(.delayed), m = model(b, followSystem: true)
        m.sessions.endCondition = .duration; m.sessions.durationMinutes = 1
        let now = Date()
        await m.sessions.start(now: now); XCTAssertTrue(m.sessions.isActive)
        await m.changeDisplayPrevention(true)
        XCTAssertTrue(m.sessions.effectivePreventDisplaySleep)
        XCTAssertFalse(m.sessions.preventDisplaySleep)
        let effects = try XCTUnwrap(m.sessionEffects as? LockPreferenceEffects)
        XCTAssertTrue(effects.appliedDisplayPrevention)
        await m.sessions.tick(now: now.addingTimeInterval(60))
        XCTAssertFalse(m.sessions.isActive); XCTAssertEqual(m.active, .normal)
        XCTAssertFalse(effects.appliedDisplayPrevention); XCTAssertGreaterThan(effects.releases, 0)
    }
    func testDefaultStillRequiresImmediateAndUnknownNeverBecomesVerified() async {
        let b = LockPreferenceBackend(.off), m = model(b, followSystem: false)
        await m.choose(.desk); XCTAssertNil(m.active); XCTAssertEqual(m.pending, .desk)
        let unknown = model(LockPreferenceBackend(.unknown), followSystem: true)
        await unknown.choose(.background); XCTAssertNil(unknown.active); XCTAssertTrue(unknown.error)
    }
    func testChangingPolicyPersistsAndRequiringProtectionReleasesUnprotectedWork() async {
        let b = LockPreferenceBackend(.off), m = model(b, followSystem: true)
        await m.choose(.desk); XCTAssertEqual(m.active, .desk)
        await m.setRequireImmediateLock(true)
        XCTAssertEqual(m.pending, .normal)
        let state = await b.snapshot(); XCTAssertFalse(state.idleSleepPrevented == true)
        let restored = AppModel(backend: b, preferences: m.preferences)
        XCTAssertTrue(restored.requiresImmediateLock)
        await m.setRequireImmediateLock(false)
        XCTAssertEqual(m.active, .normal); XCTAssertNil(m.pending)
        XCTAssertFalse(AppModel(backend: b, preferences: m.preferences).requiresImmediateLock)
    }
    func testFollowingSystemAllowsScheduledSaverButLockRequiresImmediateAuthentication() async {
        let b = LockPreferenceBackend(.off), m = model(b, followSystem: true)
        await m.choose(.desk)
        let c = m.idlePolicy; var locks = 0, savers = 0
        c.lockEnabled = true; c.screenSaverEnabled = true; c.lockMinutes = 1; c.screenSaverMinutes = 1
        c.idleProvider = { 120 }; c.unlockedProvider = { true }
        c.lockAction = { locks += 1 }; c.screenSaverAction = { savers += 1 }
        await c.tick(); XCTAssertEqual(locks, 0); XCTAssertEqual(savers, 1)
        await b.setLock(.immediate); await m.refresh(); await c.tick()
        XCTAssertEqual(locks, 1); XCTAssertEqual(savers, 1)
    }

    func testLockRechecksSystemAuthenticationDuringPreflight() async {
        let b = LockPreferenceBackend(.immediate), m = model(b, followSystem: true)
        await m.choose(.desk)
        let c = m.idlePolicy; var locks = 0
        c.lockEnabled = true; c.lockMinutes = 1; c.idleProvider = { 120 }; c.unlockedProvider = { true }
        c.lockAction = { locks += 1 }
        await b.setLock(.off)
        await c.tick()
        XCTAssertEqual(locks, 0)
    }

}
