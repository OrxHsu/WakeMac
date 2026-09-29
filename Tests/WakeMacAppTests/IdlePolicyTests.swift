import XCTest
@testable import WakeMac

@MainActor final class IdlePolicyTests: XCTestCase {
    private func controller() -> IdlePolicyController { IdlePolicyController(preferences: UserDefaults(suiteName: "IdleTests." + UUID().uuidString)!) }
    func testLockOnlyFiresWithVerifiedWorkAndUnlockedStateAndRearmsOnActivity() async {
        let c = controller(); var working = false, unlocked = true, idle = 120.0, locks = 0
        c.lockEnabled = true; c.lockMinutes = 1
        c.workingProvider = { working }; c.unlockedProvider = { unlocked }; c.idleProvider = { idle }; c.lockAction = { locks += 1 }
        await c.tick(); XCTAssertEqual(locks, 0)
        working = true; unlocked = false; await c.tick(); XCTAssertEqual(locks, 0)
        unlocked = true; await c.tick(); await c.tick(); XCTAssertEqual(locks, 1)
        idle = 0; await c.tick(); idle = 120; await c.tick(); XCTAssertEqual(locks, 2)
    }
    func testTransientIdleActionFailureCanRetryInSameIdlePeriod() async {
        struct Temporary: Error {}
        for lock in [true, false] {
            let c = controller(); var attempts = 0
            c.lockEnabled = lock; c.screenSaverEnabled = !lock
            c.lockMinutes = 1; c.screenSaverMinutes = 1
            c.workingProvider = { true }; c.unlockedProvider = { true }; c.idleProvider = { 120 }
            let action: () async throws -> Void = { attempts += 1; if attempts == 1 { throw Temporary() } }
            c.lockAction = action; c.screenSaverAction = action
            await c.tick(); await c.tick(); await c.tick()
            XCTAssertEqual(attempts, 2)
        }
    }
    func testNewActivityDuringPreflightPreventsDelayedLock() async {
        let c = controller(); var idle = 120.0, locks = 0
        c.lockEnabled = true; c.lockMinutes = 1; c.workingProvider = { true }; c.unlockedProvider = { true }
        c.idleProvider = { idle }; c.preflight = { idle = 0; return true }; c.lockAction = { locks += 1 }
        await c.tick(); XCTAssertEqual(locks, 0)
    }
    func testPreventScreenSaverChoiceBlocksScheduledScreenSaverAndUnknownIdleNeverActs() async {
        let c = controller(); var idle = Double.nan, allowed = false, starts = 0
        c.screenSaverEnabled = true; c.screenSaverMinutes = 1
        c.workingProvider = { true }; c.unlockedProvider = { true }; c.idleProvider = { idle }; c.allowsScreenSaver = { allowed }; c.screenSaverAction = { starts += 1 }
        await c.tick(); idle = 120; await c.tick(); XCTAssertEqual(starts, 0)
        allowed = true; await c.tick(); XCTAssertEqual(starts, 1)
    }
}
