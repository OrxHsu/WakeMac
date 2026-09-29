import XCTest
@testable import WakeMacCore
final class NativeStateTests: XCTestCase {
    func testDeskRejectsMissingOrUnverifiedNativeAssertion() {
        var s = Snapshot(sleepDisabled: false, lockPolicy: .immediate, idleSleepPrevented: nil, displaySleepAllowed: true, backgroundLeaseActive: false)
        XCTAssertFalse(s.matches(.desk))
        s.idleSleepPrevented = false; XCTAssertFalse(s.matches(.desk))
        s.idleSleepPrevented = true; XCTAssertTrue(s.matches(.desk))
    }
}
