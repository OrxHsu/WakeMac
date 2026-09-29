import XCTest
@testable import WakeMac
import WakeMacCore

actor AutomationBackend: ModeBackend {
    var current: WorkMode = .desk
    var lock: LockPolicy = .immediate
    var sleeps = 0
    var changes: [WorkMode] = []
    var hold = false
    var gate: CheckedContinuation<Void, Never>?
    func holdPower() { hold = true }
    var isWaiting: Bool { gate != nil }
    func release() { gate?.resume(); gate = nil }
    func snapshot() -> Snapshot {
        Snapshot(sleepDisabled: current == .background, lockPolicy: lock, idleSleepPrevented: current != .normal, displaySleepAllowed: true, backgroundLeaseActive: current == .background)
    }
    func configurePower(_ mode: WorkMode) async {
        if hold { hold = false; await withCheckedContinuation { gate = $0 } }
        current = mode; changes.append(mode)
    }
    func requestLockPolicy(_ policy: LockPolicy) {}
    func sleepNow() { sleeps += 1 }
    func removeLock() { lock = .off }
}
@MainActor final class ConvenienceTests: XCTestCase {
    func model(_ backend: AutomationBackend) -> AppModel {
        AppModel(backend: backend, preferences: UserDefaults(suiteName: "WakeMacTests." + UUID().uuidString)!)
    }
    func testDueTimerUsesRealCoordinatorAndDefersWhileBusy() async {
        let b = AutomationBackend(), m = model(b), now = Date()
        await m.refresh(); m.automation.deadline = now
        m.busy = true
        await m.tick(now: now, battery: nil)
        XCTAssertNotNil(m.automation.deadline)
        m.busy = false
        await m.tick(now: now, battery: nil)
        XCTAssertEqual(m.active, .normal)
        let changes = await b.changes, sleeps = await b.sleeps
        XCTAssertEqual(changes, [.normal]); XCTAssertEqual(sleeps, 0)
    }
    func testBatterySleepRequiresVerifiedNormalAndLockProtection() async {
        for protected in [true, false] {
            let b = AutomationBackend(), m = model(b), now = Date()
            await m.refresh()
            await m.tick(now: now, battery: BatteryReading(percent: 19, onBattery: true))
            if !protected { await b.removeLock() }
            await m.tick(now: now.addingTimeInterval(61), battery: BatteryReading(percent: 19, onBattery: true))
            let sleeps = await b.sleeps
            XCTAssertEqual(sleeps, protected ? 1 : 0)
            XCTAssertEqual(m.pending, protected ? nil : .normal)
        }
    }
    func testManualModeSwitchAndFailureDisarmTaskSleep() async {
        let b = AutomationBackend(), m = model(b), now = Date()
        await m.refresh()
        let id = m.automation.beginJob()
        await m.choose(.background)
        m.completeJob(id: id, exitCode: 0, at: now)
        XCTAssertNil(m.automation.jobSleepAt)
        let next = m.automation.beginJob()
        m.completeJob(id: next, exitCode: 9, at: now)
        await m.tick(now: now.addingTimeInterval(90), battery: nil)
        let sleeps = await b.sleeps; XCTAssertEqual(sleeps, 0)
    }
    func testCommandRunsThroughAppModelAndCancellationPreservesResult() async {
        let b = AutomationBackend()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let m = AppModel(backend: b, preferences: UserDefaults(suiteName: "WakeMacTests." + UUID().uuidString)!, jobLogDirectory: dir)
        defer { try? FileManager.default.removeItem(at: dir) }
        await m.refresh()
        await m.startJob(command: "printf model-success", directory: "/tmp")
        XCTAssertNotNil(m.automation.jobSleepAt)
        XCTAssertFalse(m.jobRunning)
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(m.jobLogURL), encoding: .utf8), "model-success")
        m.cancelAutomaticSleep()
        await m.tick(now: Date().addingTimeInterval(90), battery: nil)
        let sleeps = await b.sleeps; XCTAssertEqual(sleeps, 0)
        XCTAssertTrue(m.history.contains { $0.text.contains("命令成功") })
    }
    func testHistoryPersistsAndIsBoundedWithoutCommandBody() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("history.json"), store = HistoryStore(url: dir.appendingPathComponent("history.json"))
        for i in 0..<205 { store.append("event \(i)") }
        let reread = HistoryStore(url: url)
        XCTAssertEqual(reread.entries.count, 200)
        XCTAssertEqual(reread.entries.first?.text, "event 204")
    }
    func testQuitDoesNotAbandonRunningCommandAndDisarmsSleep() async {
        let b = AutomationBackend(), m = model(b)
        await m.refresh(); m.jobRunning = true
        _ = m.automation.beginJob()
        var quit = false; m.quitApplication = { quit = true }
        await m.requestQuit()
        XCTAssertFalse(quit); XCTAssertFalse(m.quitWhenReady); XCTAssertFalse(m.automation.jobArmed)
    }
    func testDuplicateHotkeysAreRejectedWithoutReplacingSavedBindings() {
        let keys = GlobalHotKeys(preferences: UserDefaults(suiteName: "WakeMacTests." + UUID().uuidString)!)
        var duplicate = ShortcutBinding.defaults; duplicate[1].key = duplicate[0].key
        keys.apply(duplicate, enabled: true)
        XCTAssertEqual(keys.bindings, ShortcutBinding.defaults)
        XCTAssertTrue(keys.message.contains("相同快捷键"))
    }
    func testConnectingACDuringNormalCleanupCancelsBatterySleep() async {
        let b = AutomationBackend(), m = model(b), now = Date()
        await m.refresh()
        await m.tick(now: now, battery: BatteryReading(percent: 19, onBattery: true))
        await b.holdPower()
        let pending = Task { await m.tick(now: now.addingTimeInterval(61), battery: BatteryReading(percent: 19, onBattery: true)) }
        for _ in 0..<200 {
            if await b.isWaiting { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        await m.tick(now: now.addingTimeInterval(62), battery: BatteryReading(percent: 19, onBattery: false))
        await b.release(); await pending.value
        let sleeps = await b.sleeps; XCTAssertEqual(sleeps, 0)
    }
    func testCancelTargetsTheDisplayedEarliestCountdown() async {
        let b = AutomationBackend(), m = model(b), now = Date()
        await m.refresh(); m.now = now
        let id = m.automation.beginJob(); m.completeJob(id: id, exitCode: 0, at: now)
        m.automation.deadline = now.addingTimeInterval(30)
        XCTAssertTrue(m.countdownText?.contains("恢复正常") == true)
        m.cancelVisibleCountdown()
        XCTAssertNil(m.automation.deadline); XCTAssertNotNil(m.automation.jobSleepAt)
    }
    func testMenuCountdownCanBeHidden() async {
        let b = AutomationBackend(), m = model(b), now = Date()
        await m.refresh(); m.now = now; m.automation.deadline = now.addingTimeInterval(61)
        XCTAssertEqual(m.menuText, "桌面 · 2m")
        m.setMenuLabel(false); XCTAssertEqual(m.menuText, "")
    }
}
