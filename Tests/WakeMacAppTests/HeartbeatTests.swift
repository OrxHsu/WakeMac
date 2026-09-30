import XCTest
@testable import WakeMac
import WakeMacCore

private actor HeartbeatLease: BackgroundLeaseClient {
    var disabled = false
    var renewals = 0
    var lastRenewal = ProcessInfo.processInfo.systemUptime
    var failNext = false
    var pending = false
    var replyDelay: Double = 0
    func setBackground(_ enabled: Bool) async throws { disabled = enabled; lastRenewal = ProcessInfo.processInfo.systemUptime }
    func renew() async throws {
        pending = true
        if replyDelay > 0 {
            let delay = replyDelay
            await withCheckedContinuation { continuation in DispatchQueue.global().asyncAfter(deadline: .now() + delay) { continuation.resume() } }
        }
        pending = false
        if failNext { disabled = false; throw ModeError("injected connection loss") }
        guard disabled else { throw ModeError("lease ended") }
        renewals += 1; lastRenewal = ProcessInfo.processInfo.systemUptime
    }
    func configureFailure() { failNext = true }
    func configureDelay(_ seconds: Double) { replyDelay = seconds }
    func power() -> String { "SleepDisabled \(disabled ? 1 : 0)" }
    func fresh(ttl: Double) -> Bool { disabled && ProcessInfo.processInfo.systemUptime - lastRenewal < ttl }
}

final class HeartbeatTests: XCTestCase {
    func testInitialPowerReadDoesNotStarveLeaseRenewal() async throws {
        let lease = HeartbeatLease()
        let backend = MacBackend(command: { path, _, _ in
            if path.hasSuffix("sysadminctl") { return "screenLock delay is immediate" }
            try await Task.sleep(nanoseconds: 300_000_000)
            return await lease.power()
        }, helper: lease, heartbeatInterval: 20_000_000)
        try await backend.configurePower(.background)
        let fresh = await lease.fresh(ttl: 0.15), renewals = await lease.renewals
        XCTAssertTrue(fresh); XCTAssertGreaterThanOrEqual(renewals, 3)
        try await backend.configurePower(.normal)
    }
    private func backend(_ lease: HeartbeatLease, readDelay: UInt64 = 0) -> MacBackend {
        MacBackend(command: { path, _, _ in
            if path.hasSuffix("sysadminctl") { if readDelay > 0 { try await Task.sleep(nanoseconds: readDelay) }; return "screenLock delay is immediate" }
            return await lease.power()
        }, helper: lease, heartbeatInterval: 20_000_000)
    }
    func testSlowSnapshotDoesNotStarveLeaseRenewalAndNormalStopsIt() async throws {
        let lease = HeartbeatLease(), backend = backend(lease, readDelay: 300_000_000)
        try await backend.configurePower(.background)
        let snapshot = try await backend.snapshot()
        XCTAssertTrue(snapshot.matches(.background))
        let fresh = await lease.fresh(ttl: 0.15), renewals = await lease.renewals
        XCTAssertTrue(fresh); XCTAssertGreaterThanOrEqual(renewals, 3)
        try await backend.configurePower(.normal)
        let stopped = await lease.renewals
        try await Task.sleep(nanoseconds: 100_000_000)
        let after = await lease.renewals, disabled = await lease.disabled
        XCTAssertEqual(after, stopped); XCTAssertFalse(disabled)
    }
    func testRenewalFailureReleasesNativeAssertionAndKeepsNestedErrorUntilExplicitRecovery() async throws {
        let lease = HeartbeatLease(), backend = backend(lease)
        try await backend.configurePower(.background); await lease.configureFailure()
        try await Task.sleep(nanoseconds: 100_000_000)
        do { _ = try await backend.snapshot(); XCTFail("failure hidden") }
        catch { XCTAssertTrue(error.localizedDescription.contains("injected connection loss")) }
        try await backend.configurePower(.normal)
        let final = try await backend.snapshot(); XCTAssertTrue(final.matches(.normal))
    }
    func testNormalDrainsInFlightReplyBeforeStartingAnotherMode() async throws {
        let lease = HeartbeatLease(), backend = backend(lease)
        await lease.configureDelay(0.08)
        try await backend.configurePower(.background)
        for _ in 0..<100 {
            if await lease.pending { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let wasPending = await lease.pending; XCTAssertTrue(wasPending)
        try await backend.configurePower(.normal)
        try await backend.configurePower(.desk)
        try await Task.sleep(nanoseconds: 120_000_000)
        let desk = try await backend.snapshot(); XCTAssertTrue(desk.matches(.desk))
        let disabled = await lease.disabled; XCTAssertFalse(disabled)
        try await backend.configurePower(.normal)
    }
}
