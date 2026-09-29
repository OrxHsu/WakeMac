import XCTest
@testable import WakeMac
import WakeMacCore

actor DelayedBackend: ModeBackend {
    var value = Snapshot(sleepDisabled: true, lockPolicy: .immediate, idleSleepPrevented: true, displaySleepAllowed: true, backgroundLeaseActive: true)
    var holdSnapshot = false
    var holdPower = false
    var readGate: CheckedContinuation<Void, Never>?
    var powerGate: CheckedContinuation<Void, Never>?
    var operations: [String] = []
    func setup(read: Bool = false, power: Bool = false) { holdSnapshot = read; holdPower = power }
    func snapshot() async -> Snapshot {
        let saved = value
        if holdSnapshot { holdSnapshot = false; await withCheckedContinuation { readGate = $0 } }
        return saved
    }
    func configurePower(_ mode: WorkMode) async {
        operations.append(mode.rawValue)
        if holdPower { holdPower = false; await withCheckedContinuation { powerGate = $0 } }
        value.idleSleepPrevented = mode != .normal
        value.sleepDisabled = mode == .background; value.backgroundLeaseActive = mode == .background
    }
    func requestLockPolicy(_ policy: LockPolicy) {}
    func sleepNow() {}
    func releaseRead() { readGate?.resume(); readGate = nil }
    func releasePower() { powerGate?.resume(); powerGate = nil }
    var reading: Bool { readGate != nil }
    var powering: Bool { powerGate != nil }
}

@MainActor final class LifecycleTests: XCTestCase {
    func makeModel(_ b: DelayedBackend) -> (AppModel, UserDefaults) {
        let defaults = UserDefaults(suiteName: "WakeMacTests." + UUID().uuidString)!
        return (AppModel(backend: b, preferences: defaults), defaults)
    }
    func waitUntil(_ condition: () async -> Bool) async {
        for _ in 0..<200 { if await condition() { return }; try? await Task.sleep(nanoseconds: 5_000_000) }
        XCTFail("Gate was not reached")
    }
    func testInterruptedFirstTransitionHasRecoveryMarkerBeforePowerMutationFinishes() async {
        let b = DelayedBackend(); await b.setup(power: true)
        let (m, prefs) = makeModel(b)
        let task = Task { await m.choose(.background) }
        await waitUntil { await b.powering }
        XCTAssertTrue(prefs.bool(forKey: "HasConfiguredMode"))
        await b.releasePower(); await task.value
    }
    func testOldRefreshCannotOverwriteNewlyVerifiedMode() async {
        let b = DelayedBackend(); await b.setup(read: true)
        let (m, _) = makeModel(b)
        let refresh = Task { await m.refresh() }
        await waitUntil { await b.reading }
        await m.choose(.desk)
        await b.releaseRead(); await refresh.value
        XCTAssertEqual(m.active, .desk)
        XCTAssertEqual(m.snapshot?.sleepDisabled, false)
    }
    func testQuitDuringTransitionQueuesNormalCleanup() async {
        let b = DelayedBackend(); await b.setup(power: true)
        let (m, _) = makeModel(b)
        let change = Task { await m.choose(.desk) }
        await waitUntil { await b.powering }
        await m.requestQuit()
        await b.releasePower(); await change.value
        XCTAssertEqual(m.active, .normal)
        XCTAssertNil(m.pending)
        let ops = await b.operations; XCTAssertTrue(ops.contains("normal"))
    }
}
