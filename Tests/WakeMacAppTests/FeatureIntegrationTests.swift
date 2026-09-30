// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 OrxHsu

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
    func testTriggerRuntimeOverridesAndQuickChangesResetOnRuleExit() async {
        let (model, observation) = fixture(), date = Date()
        var rule = model.triggers.rules[0]; rule.preventDisplaySleep = true; rule.preventScreenSaver = true; model.triggers.save(rule)
        await model.choose(.normal, automatic: true, startupRecovery: true)
        await model.tickFeatures(now: date, battery: nil)
        XCTAssertTrue(model.sessions.effectivePreventDisplaySleep); XCTAssertTrue(model.sessions.effectivePreventScreenSaver)
        XCTAssertFalse(model.sessions.preventDisplaySleep); XCTAssertFalse(model.sessions.preventScreenSaver)
        await model.changeDisplayPrevention(false)
        await model.tickFeatures(now: date.addingTimeInterval(6), battery: nil)
        XCTAssertFalse(model.sessions.effectivePreventDisplaySleep)
        observation.connected = false
        await model.tickFeatures(now: date.addingTimeInterval(12), battery: nil)
        XCTAssertNil(model.sessions.effectOverrides)
        observation.connected = true
        await model.tickFeatures(now: date.addingTimeInterval(18), battery: nil)
        XCTAssertTrue(model.sessions.effectivePreventDisplaySleep)
        await model.choose(.normal)
    }
    func testTriggerMasterDisableEndsOnlyTriggerOwnedWork() async {
        let (model, _) = fixture(), date = Date()
        await model.choose(.normal, automatic: true, startupRecovery: true)
        await model.tickFeatures(now: date, battery: nil)
        await model.setTriggersEnabled(false)
        XCTAssertEqual(model.active, .normal); XCTAssertNil(model.sessions.effectOverrides)
        await model.choose(.desk)
        await model.setTriggersEnabled(false)
        XCTAssertEqual(model.active, .desk)
        await model.choose(.normal)
    }
    func testSystemSleepNotificationPreservesManualBackgroundWork() async {
        let (model, _) = fixture()
        await model.choose(.background)
        await model.handleSystemWillSleep()
        XCTAssertEqual(model.active, .background)
        await model.choose(.normal)
    }
    func testSystemSleepNotificationPreservesTimedBackgroundDeadline() async {
        let (model, _) = fixture()
        model.sessions.defaultMode = .background
        model.sessions.endCondition = .duration
        await model.sessions.start()
        let deadline = model.sessions.deadline
        await model.handleSystemWillSleep()
        XCTAssertTrue(model.sessions.isActive)
        XCTAssertEqual(model.sessions.deadline, deadline)
        XCTAssertEqual(model.active, .background)
        await model.choose(.normal)
    }
    func testSystemSleepNotificationEndsDeskSession() async {
        let (model, _) = fixture()
        await model.sessions.start()
        await model.handleSystemWillSleep()
        XCTAssertFalse(model.sessions.isActive)
        XCTAssertEqual(model.active, .normal)
    }
    func testTransientPowerReadbackPreservesOwnedBackgroundDeadline() async {
        let (model, _) = fixture()
        model.sessions.defaultMode = .background; model.sessions.endCondition = .duration
        await model.sessions.start(); let deadline = model.sessions.deadline
        model.active = nil
        model.snapshot = Snapshot(sleepDisabled: false, lockPolicy: .immediate, idleSleepPrevented: true,
                                  displaySleepAllowed: true, backgroundLeaseActive: true)
        await model.handleSystemWillSleep()
        XCTAssertTrue(model.sessions.isActive); XCTAssertEqual(model.sessions.deadline, deadline)
        await model.choose(.normal)
    }
    func testSystemSleepNotificationPreservesRuleOwnedDeskWork() async {
        let (model, _) = fixture()
        await model.choose(.normal, automatic: true, startupRecovery: true)
        await model.tickFeatures(now: Date(), battery: nil)
        await model.handleSystemWillSleep()
        XCTAssertEqual(model.active, .desk)
        await model.choose(.normal)
    }
}
