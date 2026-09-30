// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 OrxHsu

import XCTest
import Darwin
@testable import WakeMac

final class ProcessDiscoveryTests: XCTestCase {
    func testCurrentUserProcessHasStableNativeIdentityWithoutArguments() throws {
        let current = try XCTUnwrap(ProcessDiscovery.process(pid: getpid()))
        XCTAssertEqual(current.identity.pid, getpid())
        XCTAssertGreaterThan(current.identity.startedSeconds, 0)
        XCTAssertTrue(current.executablePath.hasPrefix("/")); XCTAssertFalse(current.name.isEmpty)
        XCTAssertEqual(ProcessDiscovery.presence(of: current.identity), .running)
        let recycled = NativeProcessIdentity(pid: current.identity.pid, startedSeconds: current.identity.startedSeconds + 1, startedMicroseconds: current.identity.startedMicroseconds)
        XCTAssertEqual(ProcessDiscovery.presence(of: recycled), .exited)
        let snapshot = ProcessDiscovery.snapshot()
        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertTrue(snapshot.processes.contains { $0.identity == current.identity })
    }
    func testNativeIdentityReportsOwnedProcessExit() throws {
        let child = Process(); child.executableURL = URL(fileURLWithPath: "/bin/sleep"); child.arguments = ["0.2"]
        try child.run()
        let running = try XCTUnwrap(ProcessDiscovery.process(pid: child.processIdentifier))
        XCTAssertEqual(ProcessDiscovery.presence(of: running.identity), .running)
        child.waitUntilExit()
        XCTAssertEqual(ProcessDiscovery.presence(of: running.identity), .exited)
    }
    func testIncompleteSnapshotCannotEstablishAbsence() {
        XCTAssertFalse(ProcessDiscoverySnapshot(processes: [], unavailableCount: 1, isAvailable: true).isComplete)
        XCTAssertFalse(ProcessDiscoverySnapshot(processes: [], unavailableCount: 0, isAvailable: false).isComplete)
        XCTAssertTrue(ProcessDiscoverySnapshot(processes: [], unavailableCount: 0, isAvailable: true).isComplete)
    }
}
