import XCTest
@testable import AceClass

final class AceClassTests: XCTestCase {
    func testStorageKeyIsStableForEquivalentFolderURLs() {
        let plainURL = URL(fileURLWithPath: "/Volumes/Classes/Math101")
        let normalizedURL = URL(fileURLWithPath: "/Volumes/Classes/Math101/")

        XCTAssertEqual(
            LocalMetadataStorage.storageKey(for: plainURL),
            LocalMetadataStorage.storageKey(for: normalizedURL)
        )
    }

    func testVideoItemExtractDateSupportsShortAndLongFormats() {
        let longDate = VideoItem.extractDate(from: "lesson_20250704_intro.mp4")
        let shortDate = VideoItem.extractDate(from: "lesson_250704_intro.mp4")

        XCTAssertNotNil(longDate)
        XCTAssertEqual(longDate, shortDate)
    }

    func testVideoItemDecodesLegacyPayloadWithoutRelativePath() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "fileName": "week1.mp4",
          "displayName": "Week 1",
          "note": "Week 1",
          "watched": false
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(VideoItem.self, from: json)

        XCTAssertEqual(item.relativePath, "week1.mp4")
    }

    func testVideoItemPreservesNestedRelativePath() throws {
        let original = VideoItem(fileName: "week1.mp4", relativePath: "Week01/week1.mp4")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VideoItem.self, from: data)

        XCTAssertEqual(decoded.relativePath, "Week01/week1.mp4")
    }

    @MainActor
    func testLoadCoursesSupportsMixedRootVideosAndCourseFolders() async throws {
        let rootURL = try makeTempDirectory()
        try Data().write(to: rootURL.appendingPathComponent("root.mp4"))

        let childCourseURL = rootURL.appendingPathComponent("Math", isDirectory: true)
        try FileManager.default.createDirectory(at: childCourseURL, withIntermediateDirectories: true)
        try Data().write(to: childCourseURL.appendingPathComponent("lesson1.mp4"))

        let appState = AppState(loadPersistedBookmark: false)
        await appState.loadCourses(from: rootURL)
        let loaded = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            appState.courses.count == 2
        }

        XCTAssertTrue(loaded)
        XCTAssertEqual(appState.courses.count, 2)
    }

    @MainActor
    func testLoadCoursesExpandsGroupingFoldersToActualCourses() async throws {
        let rootURL = try makeTempDirectory()
        let groupingURL = rootURL.appendingPathComponent("Science", isDirectory: true)
        let biologyURL = groupingURL.appendingPathComponent("Biology", isDirectory: true)
        let chemistryURL = groupingURL.appendingPathComponent("Chemistry", isDirectory: true)

        try FileManager.default.createDirectory(at: biologyURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: chemistryURL, withIntermediateDirectories: true)
        try Data().write(to: biologyURL.appendingPathComponent("bio01.mp4"))
        try Data().write(to: chemistryURL.appendingPathComponent("chem01.mp4"))

        let appState = AppState(loadPersistedBookmark: false)
        await appState.loadCourses(from: rootURL)
        let loaded = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            Set(appState.courses.map { $0.folderURL.lastPathComponent }) == ["Biology", "Chemistry"]
        }

        let names = Set(appState.courses.map { $0.folderURL.lastPathComponent })
        XCTAssertTrue(loaded)
        XCTAssertEqual(names, ["Biology", "Chemistry"])
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    @MainActor
    private func waitUntil(
        timeoutNanoseconds: UInt64,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let pollInterval: UInt64 = 50_000_000
        let maxAttempts = max(1, Int(timeoutNanoseconds / pollInterval))

        for _ in 0..<maxAttempts {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: pollInterval)
        }

        if condition() {
            return true
        }
        return false
    }
}
