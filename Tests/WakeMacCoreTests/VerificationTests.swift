// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 OrxHsu

import XCTest
@testable import WakeMacCore
final class VerificationTests: XCTestCase {
    func testNormalRejectsEnabledOrUnknownBackgroundLease() {
        var s = Snapshot(sleepDisabled: false, lockPolicy: .immediate, idleSleepPrevented: false, displaySleepAllowed: true, backgroundLeaseActive: true)
        XCTAssertFalse(s.matches(.normal))
        s.backgroundLeaseActive = nil; XCTAssertFalse(s.matches(.normal))
    }
    func testBackgroundRequiresBothOwnedLeaseAndSystemReadback() {
        var s = Snapshot(sleepDisabled: true, lockPolicy: .immediate, idleSleepPrevented: true, displaySleepAllowed: true, backgroundLeaseActive: false)
        XCTAssertFalse(s.matches(.background))
        s.backgroundLeaseActive = true; XCTAssertTrue(s.matches(.background))
        s.sleepDisabled = nil; XCTAssertFalse(s.matches(.background))
        s.sleepDisabled = false; XCTAssertFalse(s.matches(.background))
    }
}
