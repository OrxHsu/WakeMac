import XCTest
@testable import WakeMacCore

private final class FakeSleepSwitch: SleepSwitch {
    var disabled = false
    var failRestore = false
    var ignoreEnable = false
    var source: SleepPowerSource?
    var enables = 0
    func powerSource() -> SleepPowerSource? { source }
    func read() throws -> Bool { disabled }
    func setDisabled(_ enabled: Bool) throws {
        if enabled { enables += 1 }
        if !enabled && failRestore { throw ModeError("restore failed") }
        if !enabled || !ignoreEnable { disabled = enabled }
    }
}

final class SleepLeaseTests: XCTestCase {
    func testOwnedLeaseRepairsDelayedResetAfterPowerTransition() throws {
        let power = FakeSleepSwitch(); power.source = .external
        let lease = SleepLease(power: power), owner = UUID()
        try lease.begin(owner: owner, uptime: 1000)
        power.source = .battery
        try lease.renew(owner: owner, uptime: 1005)
        power.disabled = false
        try lease.renew(owner: owner, uptime: 1015)
        XCTAssertTrue(power.disabled); XCTAssertEqual(power.enables, 2)
        power.source = .external; power.disabled = false
        try lease.renew(owner: owner, uptime: 1020)
        XCTAssertTrue(power.disabled); XCTAssertEqual(power.enables, 3)
        try lease.end(owner: owner); XCTAssertFalse(power.disabled)
    }
    func testResetOnUnchangedSourceIsNotOverwritten() throws {
        let power = FakeSleepSwitch(); power.source = .external
        let lease = SleepLease(power: power), owner = UUID()
        try lease.begin(owner: owner, uptime: 1000); power.disabled = false
        XCTAssertThrowsError(try lease.renew(owner: owner, uptime: 1005))
        XCTAssertFalse(power.disabled); XCTAssertEqual(power.enables, 1)
    }
    func testUnknownPowerSourceCannotAuthorizeRepair() throws {
        let power = FakeSleepSwitch(); power.source = .external
        let lease = SleepLease(power: power), owner = UUID()
        try lease.begin(owner: owner, uptime: 1000)
        power.source = nil; power.disabled = false
        XCTAssertThrowsError(try lease.renew(owner: owner, uptime: 1005))
        XCTAssertFalse(power.disabled)
    }
    func testRepairWindowEndsWhileLeaseContinuesRenewing() throws {
        let power = FakeSleepSwitch(); power.source = .external
        let lease = SleepLease(power: power), owner = UUID()
        try lease.begin(owner: owner, uptime: 1000); power.source = .battery
        try lease.renew(owner: owner, uptime: 1005)
        try lease.renew(owner: owner, uptime: 1020)
        power.disabled = false
        XCTAssertThrowsError(try lease.renew(owner: owner, uptime: 1026))
        XCTAssertFalse(power.disabled)
    }
    func testExpiredOrDifferentOwnerCannotRepairPowerTransition() throws {
        let power = FakeSleepSwitch(); power.source = .external
        let lease = SleepLease(power: power), owner = UUID()
        try lease.begin(owner: owner, uptime: 1000); power.source = .battery; power.disabled = false
        XCTAssertThrowsError(try lease.renew(owner: UUID(), uptime: 1005))
        XCTAssertThrowsError(try lease.renew(owner: owner, uptime: 1031))
        XCTAssertFalse(power.disabled); XCTAssertEqual(power.enables, 1)
    }
    func testFailedRepairIsRejectedAndExplicitEndStillCleansLease() throws {
        let power = FakeSleepSwitch(); power.source = .external
        let lease = SleepLease(power: power), owner = UUID()
        try lease.begin(owner: owner, uptime: 1000)
        power.source = .battery; power.disabled = false; power.ignoreEnable = true
        XCTAssertThrowsError(try lease.renew(owner: owner, uptime: 1005))
        try lease.end(owner: owner)
        power.ignoreEnable = false
        XCTAssertThrowsError(try lease.renew(owner: owner, uptime: 1010))
        XCTAssertFalse(power.disabled)
    }

    func testNeverAdoptsAnotherAppsGlobalPrevention() throws {
        let power = FakeSleepSwitch(); power.disabled = true
        let lease = SleepLease(power: power)
        XCTAssertThrowsError(try lease.begin(owner: UUID(), uptime: 1_000))
        XCTAssertTrue(power.disabled)
    }
    func testHeartbeatExpiryRestoresSleepAndCannotRenewExpiredLease() throws {
        let power = FakeSleepSwitch(); let lease = SleepLease(power: power)
        let owner = UUID(); let start: TimeInterval = 1_000
        try lease.begin(owner: owner, uptime: start)
        try lease.renew(owner: owner, uptime: start + 20)
        try lease.expire(uptime: start + 40)
        XCTAssertTrue(power.disabled)
        try lease.expire(uptime: start + 51)
        XCTAssertFalse(power.disabled)
        XCTAssertThrowsError(try lease.renew(owner: owner, uptime: start + 52))
    }
    func testAnotherClientCannotReplaceOrReleaseLease() throws {
        let power = FakeSleepSwitch(); let lease = SleepLease(power: power)
        let owner = UUID(); let other = UUID()
        try lease.begin(owner: owner, uptime: 1_000)
        XCTAssertThrowsError(try lease.begin(owner: other, uptime: 1_000))
        XCTAssertThrowsError(try lease.renew(owner: other, uptime: 1_000))
        try lease.end(owner: other)
        XCTAssertTrue(power.disabled)
        try lease.end(owner: owner)
        XCTAssertFalse(power.disabled)
    }
    func testFailedRestoreRetainsLeaseForWatchdogRetry() throws {
        let power = FakeSleepSwitch(); let lease = SleepLease(power: power)
        let owner = UUID(); let uptime: TimeInterval = 1_000
        try lease.begin(owner: owner, uptime: uptime)
        power.failRestore = true
        XCTAssertThrowsError(try lease.end(owner: owner))
        power.failRestore = false
        try lease.expire(uptime: uptime + 31)
        XCTAssertFalse(power.disabled)
    }
    func testUnverifiedEnableIsRejectedAndCanBeCleanedUp() throws {
        let power = FakeSleepSwitch(); power.ignoreEnable = true
        let lease = SleepLease(power: power); let owner = UUID()
        XCTAssertThrowsError(try lease.begin(owner: owner, uptime: 1_000))
        try lease.end(owner: owner)
        XCTAssertFalse(power.disabled)
    }
}
