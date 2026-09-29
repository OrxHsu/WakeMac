import XCTest
@testable import WakeMacCore

final class AutomationTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1000)
    func testDeadlineRestoresNormalOnce() {
        var p = AutomationPolicy(); p.deadline = now
        XCTAssertEqual(p.evaluate(now: now, mode: .desk, battery: nil), [.restoreNormal])
        XCTAssertTrue(p.evaluate(now: now, mode: .desk, battery: nil).isEmpty)
    }
    func testBatteryWarningCountdownAndSleepOnce() {
        var p = AutomationPolicy()
        XCTAssertEqual(p.evaluate(now: now, mode: .background, battery: BatteryReading(percent: 24, onBattery: true)), [.batteryWarning(24)])
        XCTAssertEqual(p.evaluate(now: now, mode: .background, battery: BatteryReading(percent: 20, onBattery: true)), [.batteryCountdown])
        XCTAssertEqual(p.evaluate(now: now.addingTimeInterval(59), mode: .background, battery: BatteryReading(percent: 20, onBattery: true)), [])
        XCTAssertEqual(p.evaluate(now: now.addingTimeInterval(60), mode: .background, battery: BatteryReading(percent: 20, onBattery: true)), [.sleepForBattery])
        XCTAssertTrue(p.evaluate(now: now.addingTimeInterval(120), mode: .background, battery: BatteryReading(percent: 19, onBattery: true)).isEmpty)
    }
    func testACUnknownAndCancelInvalidateCountdown() {
        for reading: BatteryReading? in [nil, BatteryReading(percent: 20, onBattery: false)] {
            var p = AutomationPolicy()
            _ = p.evaluate(now: now, mode: .desk, battery: BatteryReading(percent: 19, onBattery: true))
            _ = p.evaluate(now: now.addingTimeInterval(61), mode: .desk, battery: reading)
            XCTAssertNil(p.batterySleepAt)
        }
        var p = AutomationPolicy()
        _ = p.evaluate(now: now, mode: .desk, battery: BatteryReading(percent: 19, onBattery: true))
        p.cancelBatterySleep()
        XCTAssertTrue(p.evaluate(now: now.addingTimeInterval(90), mode: .desk, battery: BatteryReading(percent: 18, onBattery: true)).isEmpty)
    }
    func testNormalNeverAutomaticallySleepsAndInvalidBatteryIsUnknown() {
        var p = AutomationPolicy(); p.deadline = now
        XCTAssertTrue(p.evaluate(now: now, mode: .normal, battery: BatteryReading(percent: 1, onBattery: true)).isEmpty)
        XCTAssertTrue(p.evaluate(now: now, mode: .desk, battery: BatteryReading(percent: -1, onBattery: true)).isEmpty)
        XCTAssertNil(p.batterySleepAt)
    }
    func testTaskSleepIsCancelledByNewManualIntentAndFailure() {
        var p = AutomationPolicy(); let id = p.beginJob()
        p.cancelJobSleep()
        p.finishJob(id: id, success: true, now: now)
        XCTAssertNil(p.jobSleepAt)
        let next = p.beginJob(); p.finishJob(id: next, success: false, now: now)
        XCTAssertNil(p.jobSleepAt)
        let success = p.beginJob(); p.finishJob(id: success, success: true, now: now)
        XCTAssertEqual(p.evaluate(now: now.addingTimeInterval(60), mode: .desk, battery: nil), [.sleepForJob])
    }
}
