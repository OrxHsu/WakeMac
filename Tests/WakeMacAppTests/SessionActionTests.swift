// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 OrxHsu

import XCTest
import Carbon
@testable import WakeMac
import WakeMacCore

@MainActor final class SessionActionTests: XCTestCase {
    private func preferences() -> UserDefaults { UserDefaults(suiteName: "SessionActions." + UUID().uuidString)! }
    private func model() -> AppModel { AppModel(backend: AutomationBackend(), preferences: preferences()) }
    func testLegacyShortcutsMigrateWithoutReplacingCustomBindingsOrEnablingNewActions() throws {
        let data = Data("[{\"id\":1,\"key\":0,\"modifiers\":768},{\"id\":2,\"key\":11,\"modifiers\":768},{\"id\":3,\"key\":8,\"modifiers\":768}]".utf8)
        let saved = try JSONDecoder().decode([ShortcutBinding].self, from: data)
        let migrated = ShortcutBinding.migrated(saved)
        XCTAssertEqual(migrated.count, 11); XCTAssertEqual(Array(migrated.prefix(3)), saved)
        XCTAssertTrue(migrated.dropFirst(3).allSatisfy { !$0.enabled })
        let p = preferences(); p.set(data, forKey: "Shortcuts")
        XCTAssertEqual(GlobalHotKeys(preferences: p).bindings, migrated)
    }
    func testOnlyEnabledShortcutDuplicatesConflictAndInvalidCatalogIsRejected() {
        let h = GlobalHotKeys(preferences: preferences()); var bindings = h.bindings
        bindings[3].key = bindings[0].key
        h.apply(bindings, enabled: false); XCTAssertEqual(h.bindings, bindings)
        bindings[3].enabled = true
        h.apply(bindings, enabled: false); XCTAssertTrue(h.message.contains("相同")); XCTAssertFalse(h.bindings[3].enabled)
        h.apply(Array(bindings.prefix(3)), enabled: false); XCTAssertTrue(h.message.contains("列表无效"))
    }
    func testScriptsChangeIdleDefaultsButActiveOverridesDoNotOverwriteThem() async throws {
        let m = model()
        _ = try await ScriptControlAction.preventDisplay.perform(model: m)
        XCTAssertTrue(m.sessions.preventDisplaySleep)
        await m.choose(.desk)
        _ = try await ScriptControlAction.allowDisplay.perform(model: m)
        XCTAssertFalse(m.sessions.effectivePreventDisplaySleep); XCTAssertTrue(m.sessions.preventDisplaySleep)
        let result0 = try await ScriptControlAction.displayAllowed.perform(model: m) as? Bool
        XCTAssertEqual(result0, true)
        await m.choose(.normal)
        XCTAssertTrue(m.sessions.effectivePreventDisplaySleep); XCTAssertNil(m.sessions.effectOverrides)
    }
    func testScriptExtendRejectsBadInputWithoutChangingActiveDeadline() async throws {
        let m = model(); m.sessions.endCondition = .duration; m.sessions.durationMinutes = 2
        await m.sessions.start(); let deadline = try XCTUnwrap(m.sessions.deadline)
        do { _ = try await ScriptControlAction.extend.perform(model: m, arguments: ["minutes": -1]); XCTFail("invalid accepted") } catch {}
        XCTAssertEqual(m.sessions.deadline, deadline)
        _ = try await ScriptControlAction.extend.perform(model: m, arguments: ["minutes": 15])
        XCTAssertEqual(m.sessions.deadline, deadline.addingTimeInterval(900))
        await m.choose(.normal)
    }
    func testScriptQueriesAndTriggerMasterControl() async throws {
        let m = model()
        let result1 = try await ScriptControlAction.remaining.perform(model: m) as? Int
        XCTAssertEqual(result1, -3)
        _ = try await ScriptControlAction.disableTriggers.perform(model: m)
        XCTAssertFalse(m.triggers.enabled)
        _ = try await ScriptControlAction.enableTriggers.perform(model: m)
        XCTAssertTrue(m.triggers.enabled)
        await m.choose(.desk)
        let result2 = try await ScriptControlAction.active.perform(model: m) as? Bool
        XCTAssertEqual(result2, true)
        let result3 = try await ScriptControlAction.remaining.perform(model: m) as? Int
        XCTAssertEqual(result3, 0)
        await m.choose(.normal)
    }
    func testDefaultSessionUsesChosenDurationAndToggleEndsIt() async {
        let m = model(); m.behavior.defaultIndefinite = false; m.behavior.defaultMinutes = 3
        await m.performShortcut(4)
        XCTAssertTrue(m.sessions.isActive); XCTAssertNotNil(m.sessions.deadline)
        XCTAssertEqual(m.sessions.durationMinutes, 3)
        await m.performShortcut(4)
        XCTAssertFalse(m.sessions.isActive); XCTAssertEqual(m.active, .normal)
    }
    func testScriptLidModeChangePreservesMonitoredSessionDeadline() async throws {
        let m = model(); m.sessions.endCondition = .duration; m.sessions.durationMinutes = 2
        await m.sessions.start(); let deadline = m.sessions.deadline
        _ = try await ScriptControlAction.enableClosed.perform(model: m)
        XCTAssertTrue(m.sessions.isActive); XCTAssertEqual(m.sessions.deadline, deadline); XCTAssertEqual(m.active, .background)
        _ = try await ScriptControlAction.disableClosed.perform(model: m)
        XCTAssertTrue(m.sessions.isActive); XCTAssertEqual(m.sessions.deadline, deadline); XCTAssertEqual(m.active, .desk)
        await m.choose(.normal)
    }
}

@MainActor final class BehaviorPreferencesTests: XCTestCase {
    private func fixture() -> BehaviorPreferences { BehaviorPreferences(preferences: UserDefaults(suiteName: "Behavior." + UUID().uuidString)!) }
    func testLaunchAndWakeActionsAreOptInAndNoStatisticsBeforeEnabling() {
        let p = fixture(); XCTAssertFalse(p.startAtLaunch); XCTAssertFalse(p.startAfterWake)
        _ = p.sample(working: true, closed: true, docked: false, now: Date())
        XCTAssertEqual(p.awakeSeconds, 0); XCTAssertEqual(p.activations, 0)
    }
    func testStatisticsRejectSuspensionGapsAndOnlyCountVerifiedClosedTime() {
        let p = fixture(), date = Date(); p.statisticsEnabled = true
        _ = p.sample(working: true, closed: true, docked: false, now: date)
        _ = p.sample(working: true, closed: true, docked: false, now: date.addingTimeInterval(5))
        _ = p.sample(working: true, closed: true, docked: false, now: date.addingTimeInterval(120))
        _ = p.sample(working: false, closed: false, docked: false, now: date.addingTimeInterval(125))
        XCTAssertEqual(p.awakeSeconds, 5); XCTAssertEqual(p.lidSeconds, 5); XCTAssertEqual(p.activations, 1)
    }
    func testReminderAndLidToneAreBoundedAndDockedToneIsSilent() {
        let p = fixture(), date = Date(); p.reminderEnabled = true; p.reminderMinutes = 1; p.lidToneEnabled = true; p.lidToneRepeat = true; p.lidToneSeconds = 30
        XCTAssertEqual(p.sample(working: true, closed: true, docked: false, now: date), [.lidTone])
        XCTAssertEqual(p.sample(working: true, closed: true, docked: false, now: date.addingTimeInterval(10)), [])
        XCTAssertEqual(p.sample(working: true, closed: true, docked: false, now: date.addingTimeInterval(60)), [.reminder, .lidTone])
        XCTAssertEqual(p.sample(working: true, closed: true, docked: true, now: date.addingTimeInterval(91)), [])
        XCTAssertEqual(p.sample(working: false, closed: false, docked: false, now: date.addingTimeInterval(150)), [])
    }
    func testNotificationEventChoicesPersistIndependently() {
        let prefs = UserDefaults(suiteName: "Events." + UUID().uuidString)!
        let n = LocalNotifier(preferences: prefs); n.sessionStart = false
        let restored = LocalNotifier(preferences: prefs)
        XCTAssertFalse(restored.allows(.sessionStart)); XCTAssertTrue(restored.allows(.sessionEnd)); XCTAssertTrue(restored.allows(.triggerChange))
    }
}
