// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 OrxHsu

import XCTest
@testable import WakeMacCore
final class CommandJobTests: XCTestCase {
    func testRealShellWorkingDirectoryExitAndBoundedOutput() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let success = try CommandJob.run(command: "pwd; printf 'finished'", directory: dir.path, logURL: dir.appendingPathComponent("ok.log"))
        XCTAssertEqual(success.exitCode, 0)
        XCTAssertTrue(try String(contentsOf: success.logURL, encoding: .utf8).contains(dir.lastPathComponent))
        let failed = try CommandJob.run(command: "printf 'failure' >&2; exit 7", directory: dir.path, logURL: dir.appendingPathComponent("fail.log"))
        XCTAssertEqual(failed.exitCode, 7)
        XCTAssertTrue(try String(contentsOf: failed.logURL, encoding: .utf8).contains("failure"))
        let large = try CommandJob.run(command: "head -c 10000 /dev/zero", directory: dir.path, logURL: dir.appendingPathComponent("large.log"), logLimit: 1024)
        XCTAssertTrue(large.truncated)
        XCTAssertEqual(try Data(contentsOf: large.logURL).count, 1024)
    }
    func testInvalidDirectoryFailsBeforeStartingCommand() {
        XCTAssertThrowsError(try CommandJob.run(command: "true", directory: "/does-not-exist-workmodes", logURL: URL(fileURLWithPath: "/tmp/unused-workmodes.log")))
    }
}
