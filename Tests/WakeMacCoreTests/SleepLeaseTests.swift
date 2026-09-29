import XCTest
@testable import WakeMacCore

private final class FakeSleepSwitch: SleepSwitch {
    var disabled = false
    var failRestore = false
    var ignoreEnable = false
    func read() throws -> Bool { disabled }
    func setDisabled(_ enabled: Bool) throws {
        if !enabled && failRestore { throw ModeError("restore failed") }
        if !enabled || !ignoreEnable { disabled = enabled }
    }
}

final class SleepLeaseTests: XCTestCase {
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
