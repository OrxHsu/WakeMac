// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 OrxHsu

import XCTest
@testable import WakeMac

final class NativeAssertionTests: XCTestCase {
    func testNativeIdleAssertionIsReadBackAndReleased() throws {
        let assertion = NativeSleepAssertion()
        XCTAssertEqual(assertion.active, false)
        defer { try? assertion.release() }
        try assertion.acquire()
        XCTAssertEqual(assertion.active, true)
        try assertion.acquire() // Repeated selection must not leak another assertion.
        XCTAssertEqual(assertion.active, true)
        try assertion.release()
        XCTAssertEqual(assertion.active, false)
        try assertion.release()
        XCTAssertEqual(assertion.active, false)
    }
}
