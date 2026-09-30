import XCTest
@testable import WakeMac

@MainActor final class SafariDownloadTests: XCTestCase {
    private func fixture() throws -> (URL, URL, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WakeMac.Safari." + UUID().uuidString)
        let final = root.appendingPathComponent("fixture.bin"), package = final.appendingPathExtension("download")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let data = package.appendingPathComponent(final.lastPathComponent)
        try Data([1]).write(to: data)
        return (root, final, package, data)
    }
    private func controller(_ url: URL) -> SessionController {
        let c = SessionController(preferences: UserDefaults(suiteName: "SafariTests." + UUID().uuidString)!)
        c.endCondition = .download; c.downloadURL = url; c.downloadStabilitySeconds = 10
        c.workingProvider = { true }; c.onBegin = { _ in true }
        return c
    }
    func testPackageGrowthWaitsForFinalRenameAndStability() async throws {
        for selectInnerFile in [false, true] {
        let (root, final, package, data) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(), c = controller(selectInnerFile ? data : package)
        var ended = 0; c.onEnd = { ended += 1 }
        await c.start(now: now); XCTAssertTrue(c.isActive)
        try Data([1,2]).write(to: data)
        await c.tick(now: now.addingTimeInterval(1))
        await c.tick(now: now.addingTimeInterval(100)); XCTAssertTrue(c.isActive)
        try FileManager.default.moveItem(at: data, to: final)
        try FileManager.default.removeItem(at: package)
        await c.tick(now: now.addingTimeInterval(101)); XCTAssertTrue(c.isActive)
        await c.tick(now: now.addingTimeInterval(110)); XCTAssertTrue(c.isActive)
        await c.tick(now: now.addingTimeInterval(111)); XCTAssertFalse(c.isActive); XCTAssertEqual(ended, 1)
        }
    }
    func testCancelledPackageDoesNotCompleteUnchangedOlderDestination() async throws {
        let (root, final, package, data) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([9]).write(to: final)
        let now = Date(), c = controller(package)
        c.onEnd = { XCTFail("Cancelled package must not complete an older file") }
        await c.start(now: now); XCTAssertTrue(c.isActive)
        try Data([1,2]).write(to: data)
        await c.tick(now: now.addingTimeInterval(1))
        try FileManager.default.removeItem(at: package)
        await c.tick(now: now.addingTimeInterval(100)); XCTAssertTrue(c.isActive)
        await c.tick(now: now.addingTimeInterval(110)); XCTAssertTrue(c.isActive)
        c.manualModeChanged()
    }
    func testPackageRejectsMissingWrongNamedAndSymlinkPayloads() throws {
        let (root, _, package, data) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(SessionController.readDownload(package), SessionController.readDownload(data))
        try FileManager.default.moveItem(at: data, to: package.appendingPathComponent("unrelated.bin"))
        XCTAssertEqual(SessionController.readDownload(package), .unavailable)
        try FileManager.default.createSymbolicLink(at: data, withDestinationURL: package.appendingPathComponent("unrelated.bin"))
        XCTAssertEqual(SessionController.readDownload(package), .unavailable)
    }
}
