import XCTest
@testable import WakeMac
import WakeMacCore

@MainActor private final class TriggerTestSource: TriggerObservationSource {
    var snapshot = TriggerSnapshot()
    var calls = 0
    var requested = Set<TriggerKind>()
    func read(kinds: Set<TriggerKind>, now: Date) async -> TriggerSnapshot { calls += 1; requested = kinds; return snapshot }
}

@MainActor private final class SuspendedTriggerSource: TriggerObservationSource {
    var pending: CheckedContinuation<Void, Never>?
    func read(kinds: Set<TriggerKind>, now: Date) async -> TriggerSnapshot {
        await withCheckedContinuation { pending = $0 }
        var snapshot = TriggerSnapshot(); snapshot.externalDisplay = true
        return snapshot
    }
}

@MainActor final class TriggerTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "WakeMacTriggerTests." + UUID().uuidString)! }
    private func condition(_ kind: TriggerKind, _ value: String = "") -> TriggerCondition { TriggerCondition(kind: kind, value: value) }

    func testDefaultAndDisabledRulesNeverObserveOrMatch() async {
        let source = TriggerTestSource(), controller = TriggerController(preferences: defaults(), source: source)
        XCTAssertTrue(controller.rules.isEmpty)
        let initial = await controller.matchingRules(now: Date(), battery: nil)
        XCTAssertTrue(initial.isEmpty)
        XCTAssertNil(controller.save(TriggerRule()))
        XCTAssertFalse(controller.rules[0].enabled)
        let disabled = await controller.matchingRules(now: Date(), battery: nil)
        XCTAssertTrue(disabled.isEmpty)
        XCTAssertEqual(source.calls, 0)
    }
    func testUnknownPermissionObservationsNeverMatchEvenInAnyRuleWithoutKnownTrue() async {
        let source = TriggerTestSource(), controller = TriggerController(preferences: defaults(), source: source)
        source.snapshot.unavailable[.wifiSSID] = "定位权限不足"
        source.snapshot.unavailable[.bluetoothDevice] = "蓝牙权限不足"
        let wifi = condition(.wifiSSID, "Office"), bluetooth = condition(.bluetoothDevice, "Keyboard")
        var rule = TriggerRule(enabled: true, combination: .any, conditions: [wifi, bluetooth])
        XCTAssertNil(controller.save(rule))
        let first = await controller.matchingRules(now: Date(), battery: nil)
        XCTAssertTrue(first.isEmpty)
        XCTAssertEqual(controller.observations[wifi.id]?.state, .unknown)
        XCTAssertEqual(controller.observations[bluetooth.id]?.detail, "蓝牙权限不足")
        source.snapshot.wifiSSID = "Office"
        let second = await controller.matchingRules(now: Date(), battery: nil)
        XCTAssertEqual(second.map(\.id), [rule.id])
        rule.combination = .all; XCTAssertNil(controller.save(rule))
        let third = await controller.matchingRules(now: Date(), battery: nil)
        XCTAssertTrue(third.isEmpty)
    }
    func testAndOrMatchKnownConditionsAndIgnoreDisabledRules() async {
        let source = TriggerTestSource(), controller = TriggerController(preferences: defaults(), source: source)
        source.snapshot.externalDisplay = true; source.snapshot.acConnected = false
        let display = condition(.externalDisplay), ac = condition(.acConnected)
        let all = TriggerRule(name: "All", enabled: true, combination: .all, conditions: [display, ac])
        let any = TriggerRule(name: "Any", mode: .background, enabled: true, combination: .any, conditions: [condition(.externalDisplay), condition(.acConnected)])
        let disabled = TriggerRule(name: "Disabled", conditions: [condition(.externalDisplay)])
        XCTAssertNil(controller.save(all)); XCTAssertNil(controller.save(any)); XCTAssertNil(controller.save(disabled))
        let matches = await controller.matchingRules(now: Date(), battery: nil)
        XCTAssertEqual(matches.map(\.name), ["Any"])
        XCTAssertEqual(matches.first?.mode, .background)
        XCTAssertEqual(source.requested, [.externalDisplay, .acConnected])
    }
    func testPersistenceEditingEnableAndDeletionUseActualSavedRule() {
        let prefs = defaults(), controller = TriggerController(preferences: prefs, source: TriggerTestSource())
        var rule = TriggerRule(name: "Office", conditions: [condition(.wifiSSID, "Office")])
        XCTAssertNil(controller.save(rule)); controller.setEnabled(rule.id, true)
        let loaded = TriggerController(preferences: prefs, source: TriggerTestSource())
        XCTAssertEqual(loaded.rules.count, 1); XCTAssertTrue(loaded.rules[0].enabled)
        rule = loaded.rules[0]; rule.name = "Home"; rule.conditions[0].value = "Home"
        XCTAssertNil(loaded.save(rule))
        let updated = TriggerController(preferences: prefs, source: TriggerTestSource())
        XCTAssertEqual(updated.rules, [rule])
        updated.remove(rule.id)
        XCTAssertTrue(TriggerController(preferences: prefs, source: TriggerTestSource()).rules.isEmpty)
    }
    func testValidationRejectsEmptyConditionsInvalidFieldsAndNormalMode() {
        let controller = TriggerController(preferences: defaults(), source: TriggerTestSource())
        XCTAssertNotNil(controller.save(TriggerRule(name: "", enabled: true)))
        XCTAssertNotNil(controller.save(TriggerRule(mode: .normal, enabled: true)))
        XCTAssertNotNil(controller.save(TriggerRule(enabled: true, conditions: [])))
        for item in [condition(.ipAddress, "1.2.3"), condition(.dnsServer, "not-a-server"), condition(.cpuAbove, "NaN"), condition(.cpuAbove, "100"), condition(.idleAbove, "-1"), condition(.batteryAbove, "101"), condition(.appRunning, "Safari"), condition(.appFrontmost, "/Applications/Safari.app"), condition(.wifiSSID, " ")] {
            XCTAssertNotNil(item.validationError, item.kind.rawValue)
            XCTAssertNotNil(controller.save(TriggerRule(enabled: true, conditions: [item])))
        }
        XCTAssertTrue(controller.rules.isEmpty)
        XCTAssertNil(condition(.ipAddress, "2001:db8::1").validationError)
        XCTAssertNil(condition(.appRunning, "com.apple.Safari").validationError)
    }
    func testAppIdentityUsesExactBundleAndActualFrontmost() {
        var s = TriggerSnapshot()
        s.runningApps = ["com.apple.Safari", "com.apple.Terminal"]
        s.frontmostApp = "com.apple.Terminal"
        XCTAssertEqual(s.evaluate(condition(.appRunning, "com.apple.Safari")).state, .matched)
        XCTAssertEqual(s.evaluate(condition(.appFrontmost, "com.apple.Safari")).state, .unmatched)
        XCTAssertEqual(s.evaluate(condition(.appFrontmost, "com.apple.Terminal")).state, .matched)
        XCTAssertEqual(s.evaluate(condition(.appRunning, "com.apple.safari")).state, .unmatched)
        s.frontmostApp = nil
        XCTAssertEqual(s.evaluate(condition(.appFrontmost, "com.apple.Terminal")).state, .unknown)
    }
    func testCPURequiresDeltaHandlesIdleNiceAndCounterReset() {
        var sampler = TriggerCPUSampler()
        XCTAssertNil(sampler.sample(.init(user: 100, system: 100, idle: 100, nice: 100)))
        XCTAssertEqual(sampler.sample(.init(user: 110, system: 120, idle: 150, nice: 120)), 50)
        XCTAssertNil(sampler.sample(.init(user: 110, system: 120, idle: 150, nice: 120)))
        XCTAssertNil(sampler.sample(.init(user: 1, system: 1, idle: 1, nice: 1)))
        XCTAssertEqual(sampler.sample(.init(user: 1, system: 1, idle: 101, nice: 1)), 0)
    }
    func testAllConditionKindsReadValuesWithoutTreatingUnknownAsFalse() {
        func c(_ kind: TriggerKind, _ value: String = "") -> TriggerCondition { condition(kind, value) }
        let items: [TriggerCondition] = [c(.externalDisplay), c(.displayMirroring), c(.usbDevice, "42"), c(.bluetoothDevice, "Keyboard"), c(.appRunning, "com.apple.Safari"), c(.appFrontmost, "com.apple.Safari"), c(.batteryCharging), c(.batteryAbove, "50"), c(.acConnected), c(.acDisconnected), c(.ipAddress, "2001:db8::1"), c(.wifiSSID, "Office"), c(.ciscoVPN), c(.dnsServer, "1.1.1.1"), c(.headphones), c(.audioOutput, "headphones-uid"), c(.mountedVolume, "/Volumes/Backup"), c(.cpuAbove, "50"), c(.idleAbove, "60")]
        XCTAssertEqual(Set(items.map(\.kind)), Set(TriggerKind.allCases))
        for item in items { XCTAssertEqual(TriggerSnapshot().evaluate(item).state, .unknown, item.kind.rawValue) }
        var s = TriggerSnapshot()
        s.externalDisplay = true; s.displayMirroring = true
        s.usbDevices = [.init(id: "42", name: "Dock")]
        s.bluetoothDevices = [.init(id: "aa-bb-cc", name: "Keyboard")]
        s.runningApps = ["com.apple.Safari"]; s.frontmostApp = "com.apple.Safari"
        s.batteryCharging = true; s.batteryPercent = 70; s.acConnected = true
        s.ipAddresses = ["2001:db8:0:0:0:0:0:1"]; s.wifiSSID = "Office"; s.ciscoVPN = true; s.dnsServers = ["1.1.1.1"]
        s.headphones = true; s.audioOutput = .init(id: "headphones-uid", name: "Headphones")
        s.mountedVolumes = [.init(id: "/Volumes/Backup", name: "Backup")]
        s.cpuPercent = 70; s.idleSeconds = 100
        for item in items {
            XCTAssertEqual(s.evaluate(item).state, item.kind == .acDisconnected ? .unmatched : .matched, item.kind.rawValue)
        }
        XCTAssertEqual(s.evaluate(c(.wifiSSID, "office")).state, .unmatched)
        XCTAssertEqual(s.evaluate(c(.usbDevice, "Dock")).state, .matched)
        s.batteryCharging = false
        XCTAssertEqual(s.evaluate(c(.batteryCharging)).state, .unmatched)
        XCTAssertEqual(s.evaluate(c(.acConnected)).state, .matched)
        s.cpuPercent = 50; s.idleSeconds = 60
        XCTAssertEqual(s.evaluate(c(.cpuAbove, "50")).state, .unmatched)
        XCTAssertEqual(s.evaluate(c(.idleAbove, "60")).state, .unmatched)
    }
    func testDisabledRuleCannotMatchAnObservationAlreadyInFlight() async {
        let source = SuspendedTriggerSource(), controller = TriggerController(preferences: defaults(), source: source)
        let rule = TriggerRule(enabled: true)
        XCTAssertNil(controller.save(rule))
        let task = Task { await controller.matchingRules(now: Date(), battery: nil) }
        for _ in 0..<100 where source.pending == nil { await Task.yield() }
        guard let pending = source.pending else { XCTFail("Observation did not start"); task.cancel(); return }
        controller.setEnabled(rule.id, false)
        pending.resume(); source.pending = nil
        let matches = await task.value
        XCTAssertTrue(matches.isEmpty)
        XCTAssertTrue(controller.observations.isEmpty)
    }
    func testInvalidObservationNumbersAreUnknownAndBatteryInputDoesNotImplyCharging() async {
        var s = TriggerSnapshot(); s.cpuPercent = .infinity; s.idleSeconds = .nan; s.batteryPercent = 101
        XCTAssertEqual(s.evaluate(condition(.cpuAbove, "50")).state, .unknown)
        XCTAssertEqual(s.evaluate(condition(.idleAbove, "60")).state, .unknown)
        XCTAssertEqual(s.evaluate(condition(.batteryAbove, "50")).state, .unknown)
        let source = TriggerTestSource(), controller = TriggerController(preferences: defaults(), source: source)
        let percent = condition(.batteryAbove, "50"), ac = condition(.acConnected), charging = condition(.batteryCharging)
        let rule = TriggerRule(enabled: true, combination: .any, conditions: [percent, ac, charging])
        XCTAssertNil(controller.save(rule))
        let matches = await controller.matchingRules(now: Date(), battery: BatteryReading(percent: 60, onBattery: false))
        XCTAssertEqual(matches.map(\.id), [rule.id])
        XCTAssertEqual(controller.observations[percent.id]?.state, .matched)
        XCTAssertEqual(controller.observations[ac.id]?.state, .matched)
        XCTAssertEqual(controller.observations[charging.id]?.state, .unknown)
    }
    func testApplicationChoiceDerivesBundleIdentityAndRejectsMissingIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Example.app"), contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: String] = ["CFBundleIdentifier": "com.example.ChooserTest", "CFBundleName": "Example", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        XCTAssertEqual(TriggerController.applicationBundleIdentifier(at: app), "com.example.ChooserTest")
        XCTAssertNil(TriggerController.applicationBundleIdentifier(at: root))
        XCTAssertNil(TriggerController.applicationBundleIdentifier(at: root.appendingPathComponent("Missing.app")))
    }
    func testCurrentSuggestionsUseFriendlyLabelsAndValidSelectionValues() {
        var s = TriggerSnapshot()
        s.usbDevices = [.init(id: "registry-42", name: "Dock")]
        s.bluetoothDevices = [.init(id: "aa-bb-cc", name: "Keyboard")]
        s.audioOutput = .init(id: "persistent-audio-uid", name: "Speakers")
        s.mountedVolumes = [.init(id: "/Volumes/Backup", name: "Backup")]
        s.runningApps = ["com.example.App"]
        s.runningAppChoices = [.init(id: "com.example.App", name: "Example App")]
        XCTAssertEqual(s.suggestions(for: .usbDevice).first?.value, "Dock")
        XCTAssertEqual(s.suggestions(for: .bluetoothDevice).first?.value, "aa-bb-cc")
        XCTAssertEqual(s.suggestions(for: .audioOutput).first?.value, "persistent-audio-uid")
        XCTAssertEqual(s.suggestions(for: .mountedVolume).first?.value, "/Volumes/Backup")
        XCTAssertEqual(s.suggestions(for: .appFrontmost).first?.title, "Example App")
        XCTAssertEqual(s.suggestions(for: .appFrontmost).first?.value, "com.example.App")
        for kind: TriggerKind in [.usbDevice, .bluetoothDevice, .audioOutput, .mountedVolume, .appRunning] {
            for suggestion in s.suggestions(for: kind) { XCTAssertNil(condition(kind, suggestion.value).validationError) }
        }
        s.usbDevices?.append(.init(id: "registry-43", name: "Dock"))
        XCTAssertEqual(Set(s.suggestions(for: .usbDevice).map(\.value)), ["registry-42", "registry-43"])
    }
    func testEditorPreviewReadsUnsavedKindsWithoutSavingOrMatching() async {
        let source = TriggerTestSource(), controller = TriggerController(preferences: defaults(), source: source)
        source.snapshot.audioOutput = .init(id: "output-uid", name: "Speakers")
        let snapshot = await controller.preview(kinds: [.audioOutput])
        XCTAssertEqual(source.requested, [.audioOutput])
        XCTAssertEqual(snapshot.suggestions(for: .audioOutput).first?.title, "Speakers")
        XCTAssertTrue(controller.rules.isEmpty); XCTAssertTrue(controller.observations.isEmpty)
        XCTAssertNil(controller.lastObservedAt)
    }
    func testNativeAudioPropertyReadsReturnValidIdentifiersWhenAvailable() async {
        let source = NativeTriggerObservations()
        for _ in 0..<2 {
            let snapshot = await source.read(kinds: [.audioOutput], now: Date())
            if let output = snapshot.audioOutput { XCTAssertFalse(output.id.isEmpty); XCTAssertFalse(output.name.isEmpty) }
        }
    }
    func testNativeReadOnlyCPUSamplingAndIdleObservation() async {
        let source = NativeTriggerObservations()
        let first = await source.read(kinds: [.cpuAbove, .idleAbove], now: Date())
        XCTAssertNil(first.cpuPercent)
        XCTAssertNotNil(first.idleSeconds)
        try? await Task.sleep(nanoseconds: 30_000_000)
        let second = await source.read(kinds: [.cpuAbove, .idleAbove], now: Date())
        XCTAssertNotNil(second.cpuPercent)
        if let percent = second.cpuPercent { XCTAssertTrue((0...100).contains(percent)) }
    }
}
