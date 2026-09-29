import XCTest
@testable import WakeMacCore
final class SystemParsingTests: XCTestCase {
    func testMissingPowerSettingDoesNotBecomeSleepAllowed() {
        XCTAssertNil(SystemParsing.sleepDisabled("sleep 0 (prevented by Amphetamine)"))
        XCTAssertNil(SystemParsing.sleepDisabled("SleepDisabled unknown"))
        XCTAssertEqual(SystemParsing.sleepDisabled("System-wide power settings:\n SleepDisabled\t\t1\n"), true)
        XCTAssertEqual(SystemParsing.sleepDisabled(" SleepDisabled\t0\n"), false)
    }
    func testUsesActualSysadminctlFormatsAndDoesNotInferFromError() {
        XCTAssertEqual(SystemParsing.lockPolicy("sysadminctl[123] screenLock is off\n"), .off)
        XCTAssertEqual(SystemParsing.lockPolicy("sysadminctl[123] screenLock delay is immediate\n"), .immediate)
        XCTAssertEqual(SystemParsing.lockPolicy("screenLock delay is 300 seconds"), .delayed)
        XCTAssertEqual(SystemParsing.lockPolicy("Operation not permitted"), .unknown)
    }
    func testAppleEventResultRequiresAllFiveBooleanFields() throws {
        XCTAssertEqual(try SystemParsing.amphetamine("true, false, true, true, false\n"), [true, false, true, true, false])
        XCTAssertThrowsError(try SystemParsing.amphetamine("true, false"))
        XCTAssertThrowsError(try SystemParsing.amphetamine("true, false, true, error, false"))
    }
}
