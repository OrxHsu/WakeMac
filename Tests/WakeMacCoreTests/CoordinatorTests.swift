import XCTest
@testable import WakeMacCore

// Effects are injected at the macOS boundary; the coordinator under test is production code.
actor RecordingBackend: ModeBackend {
    var value = Snapshot(sleepDisabled: false, lockPolicy: .immediate, sessionActive: false, triggersEnabled: true, displaySleepAllowed: true, closedDisplayEnabled: false, sessionIsTrigger: false, sessionTimeRemaining: 0)
    var operations: [String] = []
    var requestedPolicies: [LockPolicy] = []
    var failPower = false
    var omitSleepDisable = false
    func setup(policy: LockPolicy = .immediate, fail: Bool = false, omit: Bool = false) { value.lockPolicy = policy; failPower = fail; omitSleepDisable = omit }
    func snapshot() -> Snapshot { value }
    func configurePower(_ mode: WorkMode) throws {
        operations.append("power:" + mode.rawValue)
        if failPower && mode != .normal { throw NSError(domain: "hardware", code: 1) }
        value.triggersEnabled = false
        value.sessionActive = mode != .normal
        value.displaySleepAllowed = true
        value.closedDisplayEnabled = mode == .background
        value.sleepDisabled = mode == .background && !omitSleepDisable
    }
    func requestLockPolicy(_ policy: LockPolicy) { operations.append("policy"); requestedPolicies.append(policy) }
    func sleepNow() { operations.append("sleep") }
}
final class CoordinatorTests: XCTestCase {
    func testEveryModeKeepsImmediatePasswordProtection() async {
        for mode in WorkMode.allCases {
            let b = RecordingBackend()
            let result = await ModeCoordinator(backend: b).select(mode)
            XCTAssertEqual(result, .active(mode))
            let requests = await b.requestedPolicies
            XCTAssertTrue(requests.isEmpty)
            let state = await b.snapshot()
            XCTAssertEqual(state.lockPolicy, .immediate)
        }
    }
    func testEveryUnprotectedModeOnlyRequestsRestoringProtection() async {
        for mode in WorkMode.allCases {
            let b = RecordingBackend(); await b.setup(policy: .off)
            let result = await ModeCoordinator(backend: b).select(mode)
            XCTAssertEqual(result, .needsLockPolicy(mode))
            let requests = await b.requestedPolicies
            XCTAssertEqual(requests, [.immediate])
        }
    }

    func testBackgroundRequiresVerifiedPowerProtect() async {
        let b = RecordingBackend(); await b.setup(omit: true)
        let r = await ModeCoordinator(backend: b).select(.background)
        guard case .failed = r else { return XCTFail("Must reject missing Power Protect") }
        let ops = await b.operations
        XCTAssertEqual(ops, ["power:background", "power:normal"])
    }
    func testBackgroundCanBecomeActiveAfterReadback() async {
        let r = await ModeCoordinator(backend: RecordingBackend()).select(.background)
        XCTAssertEqual(r, .active(.background))
    }
    func testDeskDoesNotKeepGlobalSleepDisabled() async {
        let b = RecordingBackend(); let c = ModeCoordinator(backend: b)
        _ = await c.select(.background)
        let r = await c.select(.desk); XCTAssertEqual(r, .active(.desk))
        let s = await b.snapshot(); XCTAssertEqual(s.sleepDisabled, false)
    }
    func testWorkingModeWaitsForAuthenticationBeforeChangingPower() async {
        let b = RecordingBackend(); await b.setup(policy: .off)
        let r = await ModeCoordinator(backend: b).select(.desk)
        XCTAssertEqual(r, .needsLockPolicy(.desk))
        let ops = await b.operations; XCTAssertEqual(ops, ["policy"])
    }
    func testNormalReleasesPowerBeforeWaitingForAuthentication() async {
        let b = RecordingBackend(); let c = ModeCoordinator(backend: b)
        _ = await c.select(.background)
        await b.setup(policy: .off)
        let r = await c.select(.normal)
        XCTAssertEqual(r, .needsLockPolicy(.normal))
        let ops = await b.operations; XCTAssertEqual(ops, ["power:background", "power:normal", "policy"])
        let s = await b.snapshot(); XCTAssertEqual(s.triggersEnabled, false)
        XCTAssertEqual(s.sleepDisabled, false)
    }
    func testSleepIsNotIssuedWhilePasswordRequirementIsOff() async {
        let b = RecordingBackend(); await b.setup(policy: .off)
        let r = await ModeCoordinator(backend: b).sleep()
        XCTAssertEqual(r, .needsLockPolicy(.normal))
        let ops = await b.operations; XCTAssertFalse(ops.contains("sleep"))
    }
    func testSleepFollowsVerifiedNormal() async {
        let b = RecordingBackend(); await b.setup(policy: .immediate)
        let r = await ModeCoordinator(backend: b).sleep()
        XCTAssertEqual(r, .active(.normal))
        let ops = await b.operations; XCTAssertEqual(ops, ["power:normal", "sleep"])
    }
    func testPowerFailureReleasesInhibitorAndDoesNotClaimSuccess() async {
        let b = RecordingBackend(); await b.setup(fail: true)
        let r = await ModeCoordinator(backend: b).select(.background)
        guard case .failed = r else { return XCTFail("Must surface failure") }
        let ops = await b.operations; XCTAssertEqual(ops, ["power:background", "power:normal"])
    }
}
