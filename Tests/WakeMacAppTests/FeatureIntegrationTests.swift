import XCTest
@testable import WakeMac
import WakeMacCore

@MainActor private final class IntegrationObservations: TriggerObservationSource {
    var connected = true
    func read(kinds: Set<TriggerKind>, now: Date) async -> TriggerSnapshot {
        var snapshot = TriggerSnapshot(); snapshot.externalDisplay = connected; return snapshot
    }
}
@MainActor final class FeatureIntegrationTests: XCTestCase {
    private func fixture() -> (AppModel, IntegrationObservations) {
        let observation = IntegrationObservations()
        let model = AppModel(backend: AutomationBackend(), preferences: UserDefaults(suiteName: "IntegrationTests." + UUID().uuidString)!, triggerSource: observation)
        model.triggers.save(TriggerRule(name: "Display", enabled: true, conditions: [TriggerCondition(kind: .externalDisplay)]))
        return (model, observation)
    }
    func testEnabledRuleActivatesAfterStartupRecoveryThenRestoresWhenConditionClears() async {
        let (model, observation) = fixture(), date = Date()
        await model.choose(.normal, automatic: true, startupRecovery: true)
        await model.tickFeatures(now: date, battery: nil)
        XCTAssertEqual(model.active, .desk)
        observation.connected = false
        await model.tickFeatures(now: date.addingTimeInterval(6), battery: nil)
        XCTAssertEqual(model.active, .normal)
    }
    func testManualNormalSuppressesMatchingRuleUntilItClearsAndMatchesAgain() async {
        let (model, observation) = fixture(), date = Date()
        await model.choose(.normal, automatic: true, startupRecovery: true)
        await model.tickFeatures(now: date, battery: nil)
        await model.choose(.normal)
        await model.tickFeatures(now: date.addingTimeInterval(6), battery: nil)
        XCTAssertEqual(model.active, .normal)
        observation.connected = false
        await model.tickFeatures(now: date.addingTimeInterval(12), battery: nil)
        observation.connected = true
        await model.tickFeatures(now: date.addingTimeInterval(18), battery: nil)
        XCTAssertEqual(model.active, .desk)
    }
    func testTimedSessionTakesPriorityAndCompletionCannotImmediatelyRetriggerWork() async {
        let (model, _) = fixture(), date = Date()
        await model.choose(.normal, automatic: true, startupRecovery: true)
        model.sessions.endCondition = .duration; model.sessions.durationMinutes = 1
        await model.sessions.start(now: date)
        await model.tickFeatures(now: date.addingTimeInterval(5), battery: nil)
        XCTAssertTrue(model.sessions.isActive)
        await model.tickFeatures(now: date.addingTimeInterval(61), battery: nil)
        XCTAssertEqual(model.active, .normal); XCTAssertFalse(model.sessions.isActive)
        await model.tickFeatures(now: date.addingTimeInterval(70), battery: nil)
        XCTAssertEqual(model.active, .normal)
    }
    func testChangedLockPolicyReleasesManualWorkDuringRefresh() async {
        let backend = AutomationBackend()
        let model = AppModel(backend: backend, preferences: UserDefaults(suiteName: "LockRefresh." + UUID().uuidString)!)
        await model.choose(.desk); await backend.removeLock(); await model.refresh()
        let current = await backend.current
        XCTAssertEqual(current, .normal); XCTAssertEqual(model.pending, .normal)
        XCTAssertFalse(model.keepsAwake)
    }
    func testScriptArgumentsRejectValuesOutsideSessionLimitsBeforeChangingState() throws {
        XCTAssertEqual(try ScriptSessionArguments(["minutes": NSNumber(value: 10080)]).minutes, 10080)
        XCTAssertThrowsError(try ScriptSessionArguments(["minutes": NSNumber(value: 10081)]))
        XCTAssertThrowsError(try ScriptSessionArguments(["minutes": NSNumber(value: 0.5)]))
        XCTAssertThrowsError(try ScriptSessionArguments(["mode": "normal"]))
    }
}
