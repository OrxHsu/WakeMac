// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 OrxHsu

import XCTest
import UserNotifications
@testable import WakeMac

@MainActor final class NotificationTests: XCTestCase {
    func testDeniedAuthorizationOpensSettingsWithoutRepeatingPermissionPrompt() async {
        var prompts = 0, opened: URL?
        let n = LocalNotifier(readAuthorization: { .denied }, askAuthorization: { prompts += 1; return false }, openSettings: { opened = $0; return true })
        let granted = await n.request()
        XCTAssertFalse(granted); XCTAssertEqual(prompts, 0)
        XCTAssertEqual(opened?.scheme, "x-apple.systempreferences")
        XCTAssertTrue(opened?.absoluteString.contains("Notifications-Settings.extension") == true)
        XCTAssertFalse(n.enabled)
    }
    func testFirstAuthorizationRefreshesActualStateAndDoesNotOpenSettingsWhenAllowed() async {
        var state: UNAuthorizationStatus = .notDetermined, opens = 0
        let n = LocalNotifier(readAuthorization: { state }, askAuthorization: { state = .authorized; return true }, openSettings: { _ in opens += 1; return true })
        let granted = await n.request()
        XCTAssertTrue(granted); XCTAssertTrue(n.enabled); XCTAssertEqual(opens, 0)
        state = .denied; await n.refresh(); XCTAssertFalse(n.enabled)
    }
    func testPermissionFailureIsNotReportedAsDenial() async {
        struct Unavailable: Error {}
        var opens = 0
        let n = LocalNotifier(readAuthorization: { .notDetermined }, askAuthorization: { throw Unavailable() }, openSettings: { _ in opens += 1; return true })
        let granted = await n.request()
        XCTAssertFalse(granted); XCTAssertEqual(opens, 0)
        XCTAssertTrue(n.message.contains("请求失败"))
    }
}
