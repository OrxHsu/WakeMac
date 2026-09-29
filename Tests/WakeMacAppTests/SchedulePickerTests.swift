import XCTest
@testable import WakeMac

final class SchedulePickerTests: XCTestCase {
    func calendar(_ zone: String = "Asia/Muscat") -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: zone)!
        result.firstWeekday = 2
        return result
    }
    func testCalendarGridKeepsMondayAlignmentAndLeapDay() {
        let c = calendar()
        let month = c.date(from: DateComponents(year: 2028, month: 2, day: 12))!
        let days = ScheduleCalendar.days(in: month, calendar: c)
        XCTAssertNil(days.first!) // February 1, 2028 is Tuesday.
        XCTAssertEqual(days.compactMap { $0 }.count, 29)
        XCTAssertEqual(c.component(.day, from: days.last!!), 29)
        XCTAssertEqual(c.component(.month, from: days.last!!), 2)
    }
    func testSelectedDayAndTimeArePreservedWithoutSeconds() {
        let c = calendar()
        let day = c.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 13, second: 52))!
        let value = ScheduleCalendar.date(day: day, hour: 23, minute: 59, calendar: c)!
        let parts = c.dateComponents([.year, .month, .day, .hour, .minute, .second], from: value)
        XCTAssertEqual(parts, DateComponents(year: 2026, month: 12, day: 31, hour: 23, minute: 59, second: 0))
        XCTAssertNil(ScheduleCalendar.date(day: day, hour: 24, minute: 0, calendar: c))
        XCTAssertNil(ScheduleCalendar.date(day: day, hour: 23, minute: 60, calendar: c))
    }
    func testNonexistentDSTTimeIsRejectedRatherThanShifted() {
        let c = calendar("America/Los_Angeles")
        let day = c.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        XCTAssertNil(ScheduleCalendar.date(day: day, hour: 2, minute: 30, calendar: c))
        XCTAssertNotNil(ScheduleCalendar.date(day: day, hour: 3, minute: 30, calendar: c))
    }
}
