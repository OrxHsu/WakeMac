import XCTest
import ServiceManagement
import WakeMacCore
import WakeMacPower
@testable import WakeMac

final class NativeBackendTests: XCTestCase {
    func testDesktopAndNormalUseNativeAssertionsWithoutHelperApproval() async throws {
        let backend = MacBackend()
        let initial = try await backend.snapshot()
        guard initial.sleepDisabled == false else { throw XCTSkip("Another app is changing the global sleep switch.") }
        guard initial.lockPolicy == .immediate else { throw XCTSkip("Runtime check requires existing immediate lock protection.") }
        do {
            try await backend.configurePower(.desk)
            let desk = try await backend.snapshot()
            XCTAssertTrue(desk.matches(.desk))
            try await backend.configurePower(.normal)
            let normal = try await backend.snapshot()
            XCTAssertTrue(normal.matches(.normal))
        } catch {
            try? await backend.configurePower(.normal)
            throw error
        }
    }
    func testUnapprovedBackgroundFailsAndRestoresNormal() async throws {
        guard SMAppService.daemon(plistName: PowerService.plistName).status != .enabled else {
            throw XCTSkip("This check must not alter an approved helper's global power setting.")
        }
        let backend = MacBackend()
        let initial = try await backend.snapshot()
        guard initial.sleepDisabled == false, initial.lockPolicy == .immediate else {
            throw XCTSkip("Existing power state is unsuitable for a nonprivileged runtime check.")
        }
        let result = await ModeCoordinator(backend: backend).select(.background)
        guard case .failed = result else { return XCTFail("Unapproved helper must not activate background mode.") }
        let final = try await backend.snapshot()
        XCTAssertTrue(final.matches(.normal))
    }
}
