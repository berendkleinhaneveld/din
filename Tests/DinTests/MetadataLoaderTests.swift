import XCTest

@testable import Din

final class MetadataLoaderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("din-audiofiles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    @discardableResult
    private func touch(_ relativePath: String) throws -> URL {
        let url = directory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
        return url
    }

    private func names(_ urls: [URL]) -> [String] {
        urls.map(\.lastPathComponent)
    }

    // MARK: - Discovery

    func testKeepsOnlySupportedAudioExtensions() throws {
        try touch("song.mp3")
        try touch("notes.txt")
        try touch("cover.jpg")

        let found = MetadataLoader.audioFiles(in: [directory])

        XCTAssertEqual(names(found), ["song.mp3"])
    }

    func testMatchesExtensionsCaseInsensitively() throws {
        try touch("loud.MP3")
        try touch("quiet.FlAc")

        let found = MetadataLoader.audioFiles(in: [directory])

        XCTAssertEqual(names(found), ["loud.MP3", "quiet.FlAc"])
    }

    func testRecursesIntoDirectories() throws {
        try touch("a.mp3")
        try touch("nested/b.wav")
        try touch("nested/deeper/c.aiff")

        let found = MetadataLoader.audioFiles(in: [directory])

        XCTAssertEqual(names(found), ["a.mp3", "b.wav", "c.aiff"])
    }

    func testAcceptsIndividualFilesAsWellAsDirectories() throws {
        let song = try touch("song.mp3")
        try touch("other/second.mp3")

        let found = MetadataLoader.audioFiles(in: [song, directory.appendingPathComponent("other")])

        XCTAssertEqual(names(found), ["second.mp3", "song.mp3"])
    }

    func testSkipsHiddenFiles() throws {
        try touch("visible.mp3")
        try touch(".hidden.mp3")

        let found = MetadataLoader.audioFiles(in: [directory])

        XCTAssertEqual(names(found), ["visible.mp3"])
    }

    func testIgnoresPathsThatDoNotExist() {
        let missing = directory.appendingPathComponent("missing.mp3")

        XCTAssertTrue(MetadataLoader.audioFiles(in: [missing]).isEmpty)
    }

    /// Track order is what the user sees in the playlist, so discovery sorts by
    /// file name the way Finder does — "track2" before "track10".
    func testSortsNumericallyByFileName() throws {
        try touch("track10.mp3")
        try touch("track2.mp3")
        try touch("track1.mp3")

        let found = MetadataLoader.audioFiles(in: [directory])

        XCTAssertEqual(names(found), ["track1.mp3", "track2.mp3", "track10.mp3"])
    }

    // MARK: - Metadata

    func testLoadFallsBackToTheFileNameWhenThereIsNoTitleTag() async throws {
        let url = AudioFixture.temporaryURL(extension: "caf")
        defer { AudioFixture.cleanUp(url) }
        try AudioFixture.writeBursts(to: url, seconds: 1, burstsAt: [])

        let track = await MetadataLoader.load(url: url)

        XCTAssertEqual(track.title, "fixture")
        XCTAssertEqual(track.artist, "Unknown Artist")
        XCTAssertEqual(track.album, "Unknown Album")
        XCTAssertEqual(track.duration, 1, accuracy: 0.1)
    }
}
