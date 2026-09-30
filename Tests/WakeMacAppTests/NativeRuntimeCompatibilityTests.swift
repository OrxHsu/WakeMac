import XCTest
@testable import WakeMac

@MainActor final class NativeRuntimeCompatibilityTests: XCTestCase {
    func testReadOnlyNativeObservationsAndUnavailablePermissions() async throws {
        let source = NativeTriggerObservations(), kinds = Set(TriggerKind.allCases)
        let first = await source.read(kinds: kinds, now: Date())
        XCTAssertNil(first.cpuPercent)
        try await Task.sleep(nanoseconds: 250_000_000)
        let current = await source.read(kinds: kinds, now: Date())
        XCTAssertNotNil(current.observedAt)
        if let cpu = current.cpuPercent { XCTAssertTrue(cpu.isFinite && (0...100).contains(cpu)) }
        if let battery = current.batteryPercent { XCTAssertTrue((0...100).contains(battery)) }
        if let idle = current.idleSeconds { XCTAssertTrue(idle.isFinite && idle >= 0) }
        let marker = "WakeMac.validation." + UUID().uuidString
        if current.wifiSSID == nil {
            XCTAssertEqual(current.evaluate(.init(kind: .wifiSSID, value: marker)).state, .unknown)
        }
        if current.bluetoothDevices == nil {
            XCTAssertEqual(current.evaluate(.init(kind: .bluetoothDevice, value: marker)).state, .unknown)
        }
        // Counts and availability only: do not put SSIDs, addresses, devices,
        // applications, volume paths or other private identifiers in test logs.
        let report: [String: Any] = [
            "connectedDisplayKnown": current.connectedDisplay != nil,
            "externalDisplayConnected": current.externalDisplay as Any? ?? NSNull(),
            "usbCount": current.usbDevices?.count ?? -1,
            "bluetoothKnown": current.bluetoothDevices != nil,
            "wifiKnown": current.wifiSSID != nil,
            "powerKnown": current.acConnected != nil,
            "ipCount": current.ipAddresses?.count ?? -1,
            "dnsCount": current.dnsServers?.count ?? -1,
            "vpnKnown": current.ciscoVPN != nil,
            "audioKnown": current.audioOutput != nil,
            "headphonesKnown": current.headphones != nil,
            "volumeCount": current.mountedVolumes?.count ?? -1,
            "cpuKnown": current.cpuPercent != nil,
            "idleKnown": current.idleSeconds != nil,
            "processInventoryKnown": current.processes != nil
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        print("WakeMac native observation availability: " + String(decoding: data, as: UTF8.self))
    }

    func testRealAsyncDriveAliveOnOwnedLocalDirectoryLeavesOriginalData() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WakeMac.NativeDrive." + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let values = try directory.resourceValues(forKeys: [.volumeIsLocalKey])
        guard values.volumeIsLocal == true else { throw XCTSkip("No writable local test volume") }
        let original = directory.appendingPathComponent("original.txt"), data = Data("Original test data".utf8)
        try data.write(to: original)
        let effects = NativeSessionEffects(), choices = SessionEffectChoices(driveAlive: true)
        defer { effects.release() }
        var report = effects.update(working: true, choices: choices, directories: [directory], now: Date())
        for _ in 0..<100 where report.drives[directory.path]?.contains("已同步") != true {
            try await Task.sleep(nanoseconds: 20_000_000)
            report = effects.update(working: true, choices: choices, directories: [directory], now: Date())
        }
        XCTAssertTrue(report.drives[directory.path]?.contains("已同步") == true)
        effects.release()
        XCTAssertEqual(try Data(contentsOf: original), data)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["original.txt"])
    }
}
