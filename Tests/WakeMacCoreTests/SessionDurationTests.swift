import XCTest
@testable import WakeMacCore
final class SessionDurationTests: XCTestCase {
    func testParsesInfiniteDurationAndNegativeInactiveSentinel() throws {
        let active = try SystemParsing.sessionDuration("true, false, true, false, false, 0")
        XCTAssertEqual(active, 0)
        XCTAssertEqual(try SystemParsing.sessionDuration("false, false, true, false, false, -3"), -3)
        XCTAssertThrowsError(try SystemParsing.sessionDuration("true, false, true, false, false, unknown"))
    }
}
