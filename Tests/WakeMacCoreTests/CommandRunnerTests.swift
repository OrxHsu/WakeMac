// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 OrxHsu

import XCTest
@testable import WakeMacCore
final class CommandRunnerTests: XCTestCase {
    func testCapturesBothStreamsAndPreservesLiteralArguments() throws {
        let output = try CommandRunner.run("/bin/sh", ["-c", "printf '%s' \"$1\"; printf 'diagnostic' >&2", "test", "$(secret) ; literal"])
        XCTAssertTrue(output.contains("$(secret) ; literal"))
        XCTAssertTrue(output.contains("diagnostic"))
    }
    func testRejectsExitFailureWithDiagnostic() {
        XCTAssertThrowsError(try CommandRunner.run("/bin/sh", ["-c", "echo denied >&2; exit 7"])) { e in
            XCTAssertTrue(e.localizedDescription.contains("denied"))
        }
    }
    func testTerminatesTimeoutInsteadOfHangingModeSwitch() {
        let start = Date()
        XCTAssertThrowsError(try CommandRunner.run("/bin/sleep", ["5"], timeout: 0.1)) { e in
            XCTAssertTrue(e.localizedDescription.contains("超时"))
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
}
