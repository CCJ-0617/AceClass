import XCTest
@testable import AceClass

final class AceClassTests: XCTestCase {
    func testSupportedVideoExtensionsIncludeAdditionalFormats() {
        XCTAssertTrue(AppState.supportedVideoExtensions.contains("avi"))
        XCTAssertTrue(AppState.supportedVideoExtensions.contains("mpeg"))
        XCTAssertTrue(AppState.supportedVideoExtensions.contains("mts"))
        XCTAssertTrue(AppState.supportedVideoExtensions.contains("3gp"))
    }

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

    func testVideoItemDoesNotAutofillNoteFromFileName() {
        let item = VideoItem(fileName: "week1.mp4")

        XCTAssertEqual(item.note, "")
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
    func testLoadCoursesRecognizesAdditionalSupportedFormats() async throws {
        let rootURL = try makeTempDirectory()
        let lectureURL = rootURL.appendingPathComponent("Lecture", isDirectory: true)
        let archiveURL = rootURL.appendingPathComponent("Archive", isDirectory: true)

        try FileManager.default.createDirectory(at: lectureURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archiveURL, withIntermediateDirectories: true)
        try Data().write(to: lectureURL.appendingPathComponent("lesson01.avi"))
        try Data().write(to: archiveURL.appendingPathComponent("review01.mts"))

        let appState = AppState(loadPersistedBookmark: false)
        await appState.loadCourses(from: rootURL)
        let loaded = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            Set(appState.courses.map { $0.folderURL.lastPathComponent }) == ["Lecture", "Archive"]
        }

        XCTAssertTrue(loaded)
        XCTAssertEqual(Set(appState.courses.map(\.folderURL.lastPathComponent)), ["Lecture", "Archive"])
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

    @MainActor
    func testLoadCoursesTraversesWrapperFoldersToReachNestedCourse() async throws {
        let rootURL = try makeTempDirectory()
        let ignoredURL = rootURL.appendingPathComponent("00_管理", isDirectory: true)
        let courseVideoURL = rootURL
            .appendingPathComponent("科目分類", isDirectory: true)
            .appendingPathComponent("英文", isDirectory: true)
            .appendingPathComponent("高二下英文", isDirectory: true)
            .appendingPathComponent("單元_未分類", isDirectory: true)

        try FileManager.default.createDirectory(at: ignoredURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: courseVideoURL, withIntermediateDirectories: true)
        try Data().write(to: courseVideoURL.appendingPathComponent("1140412.mkv"))

        let appState = AppState(loadPersistedBookmark: false)
        await appState.loadCourses(from: rootURL)
        let loaded = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            appState.courses.count == 1
        }

        XCTAssertTrue(loaded)
        XCTAssertEqual(appState.courses.map(\.folderURL.lastPathComponent), ["高二下英文"])
    }

    @MainActor
    func testLoadCoursesKeepsParentAsCourseWhenUnitsAndChaptersCoexist() async throws {
        let rootURL = try makeTempDirectory()
        let courseURL = rootURL
            .appendingPathComponent("數學", isDirectory: true)
            .appendingPathComponent("第六冊+複習", isDirectory: true)
        let chapterURL = courseURL.appendingPathComponent("二次曲線", isDirectory: true)
        let genericUnitURL = courseURL.appendingPathComponent("單元_未分類", isDirectory: true)

        try FileManager.default.createDirectory(at: chapterURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: genericUnitURL, withIntermediateDirectories: true)
        try Data().write(to: chapterURL.appendingPathComponent("chapter01.mp4"))
        try Data().write(to: genericUnitURL.appendingPathComponent("week01.mp4"))

        let appState = AppState(loadPersistedBookmark: false)
        await appState.loadCourses(from: rootURL)
        let loaded = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            appState.courses.count == 1
        }

        XCTAssertTrue(loaded)
        XCTAssertEqual(appState.courses.map(\.folderURL.lastPathComponent), ["第六冊+複習"])
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
