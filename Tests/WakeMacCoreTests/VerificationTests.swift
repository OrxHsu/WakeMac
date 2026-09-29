import XCTest
@testable import WakeMacCore
final class VerificationTests: XCTestCase {
    func testNormalRejectsEnabledOrUnknownClosedDisplayMode() {
        var s = Snapshot(sleepDisabled: false, lockPolicy: .immediate, sessionActive: false, triggersEnabled: false, displaySleepAllowed: true, closedDisplayEnabled: true)
        XCTAssertFalse(s.matches(.normal))
        s.closedDisplayEnabled = nil; XCTAssertFalse(s.matches(.normal))
    }
    func testWorkingModeRejectsTimedOrTriggerSessions() {
        var s = Snapshot(sleepDisabled: false, lockPolicy: .immediate, sessionActive: true, triggersEnabled: false, displaySleepAllowed: true, closedDisplayEnabled: false, sessionIsTrigger: false, sessionTimeRemaining: 300)
        XCTAssertFalse(s.matches(.desk))
        s.sessionTimeRemaining = 0; s.sessionIsTrigger = true
        XCTAssertFalse(s.matches(.desk))
        s.sessionIsTrigger = nil; XCTAssertFalse(s.matches(.desk))
        s.sessionIsTrigger = false; XCTAssertTrue(s.matches(.desk))
    }
}
