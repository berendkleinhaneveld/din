import XCTest

@testable import Din

final class M3U8Tests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("din-m3u8-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    @discardableResult
    private func touch(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
        return url
    }

    // MARK: - Writing

    func testWriteEmitsHeaderAndOneExtinfPerTrack() {
        let tracks = [
            Track(url: URL(fileURLWithPath: "/music/one.mp3"), title: "One", duration: 61),
            Track(url: URL(fileURLWithPath: "/music/two.mp3"), title: "Two", duration: 125),
        ]

        let lines = M3U8.write(tracks: tracks).components(separatedBy: "\n")

        XCTAssertEqual(lines.first, "#EXTM3U")
        XCTAssertEqual(lines[1], "#EXTINF:61,One")
        XCTAssertEqual(lines[2], "/music/one.mp3")
        XCTAssertEqual(lines[3], "#EXTINF:125,Two")
        XCTAssertEqual(lines[4], "/music/two.mp3")
    }

    func testWriteTruncatesFractionalDurations() {
        let tracks = [Track(url: URL(fileURLWithPath: "/music/one.mp3"), title: "One", duration: 61.8)]

        XCTAssertTrue(M3U8.write(tracks: tracks).contains("#EXTINF:61,One"))
    }

    func testWriteProducesATrailingNewline() {
        let tracks = [Track(url: URL(fileURLWithPath: "/music/one.mp3"), title: "One", duration: 1)]

        XCTAssertTrue(M3U8.write(tracks: tracks).hasSuffix("\n"))
    }

    // MARK: - Parsing

    func testParseResolvesAbsoluteAndRelativePaths() throws {
        let absolute = try touch("absolute.mp3")
        try touch("nested/relative.mp3")

        let contents = """
            #EXTM3U
            #EXTINF:10,Absolute
            \(absolute.path)
            #EXTINF:20,Relative
            nested/relative.mp3
            """

        let urls = M3U8.parse(contents: contents, relativeTo: directory)

        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls[0].lastPathComponent, "absolute.mp3")
        XCTAssertEqual(urls[1].lastPathComponent, "relative.mp3")
    }

    func testParseSkipsCommentsBlankLinesAndWhitespace() throws {
        try touch("song.mp3")

        let contents = """
            #EXTM3U

            # a comment
            #EXTINF:10,Song
              song.mp3

            """

        XCTAssertEqual(M3U8.parse(contents: contents, relativeTo: directory).count, 1)
    }

    /// Entries that no longer exist on disk are dropped rather than surfaced as
    /// broken tracks.
    func testParseDropsEntriesThatDoNotExist() throws {
        try touch("present.mp3")

        let contents = """
            present.mp3
            missing.mp3
            """

        let urls = M3U8.parse(contents: contents, relativeTo: directory)

        XCTAssertEqual(urls.map(\.lastPathComponent), ["present.mp3"])
    }

    func testParseReturnsEmptyForAPlaylistWithNoUsableEntries() {
        XCTAssertTrue(M3U8.parse(contents: "#EXTM3U\n", relativeTo: directory).isEmpty)
    }

    func testWrittenPlaylistParsesBackToTheSameFiles() throws {
        let first = try touch("first.mp3")
        let second = try touch("second.mp3")
        let tracks = [
            Track(url: first, title: "First", duration: 10),
            Track(url: second, title: "Second", duration: 20),
        ]

        let urls = M3U8.parse(contents: M3U8.write(tracks: tracks), relativeTo: directory)

        XCTAssertEqual(urls.map(\.path), [first.path, second.path])
    }
}
