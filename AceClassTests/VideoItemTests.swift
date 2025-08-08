import XCTest
@testable import AceClass

final class VideoItemTests: XCTestCase {
    func testExtractDateFromEightDigitFileName() throws {
        let fileName = "Lesson_20250704_notes.mp4"
        let date = VideoItem.extractDate(from: fileName)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let expectedDate = formatter.date(from: "20250704")

        XCTAssertEqual(date, expectedDate)
    }

    func testExtractDateFromSixDigitFileName() throws {
        let fileName = "Lesson_250704_notes.mp4"
        let date = VideoItem.extractDate(from: fileName)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let expectedDate = formatter.date(from: "20250704")

        XCTAssertEqual(date, expectedDate)
    }
}

final class CourseCountdownTests: XCTestCase {
    func testIsOverdueWhenTargetDateIsPast() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let pastDate = calendar.date(byAdding: .day, value: -1, to: today)!
        let course = Course(folderURL: URL(fileURLWithPath: NSTemporaryDirectory()), videos: [], targetDate: pastDate)
        XCTAssertTrue(course.isOverdue)
    }

    func testCountdownTextForVariousDates() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let futureDate = calendar.date(byAdding: .day, value: 3, to: today)!
        var course = Course(folderURL: URL(fileURLWithPath: NSTemporaryDirectory()), videos: [], targetDate: futureDate)
        XCTAssertEqual(course.countdownText, "剩餘 3 天")

        let todayCourse = Course(folderURL: URL(fileURLWithPath: NSTemporaryDirectory()), videos: [], targetDate: today)
        XCTAssertEqual(todayCourse.countdownText, "今天到期")

        let pastDate = calendar.date(byAdding: .day, value: -2, to: today)!
        course = Course(folderURL: URL(fileURLWithPath: NSTemporaryDirectory()), videos: [], targetDate: pastDate)
        XCTAssertEqual(course.countdownText, "已過期 2 天")
    }
}
