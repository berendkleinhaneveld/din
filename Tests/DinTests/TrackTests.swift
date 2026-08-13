import XCTest

@testable import Din

final class TrackTests: XCTestCase {
    private func track(
        named name: String = "song.mp3",
        title: String? = nil,
        artist: String = "Unknown Artist",
        album: String = "Unknown Album"
    ) -> Track {
        Track(
            url: URL(fileURLWithPath: "/music/\(name)"),
            title: title,
            artist: artist,
            album: album
        )
    }

    // MARK: - Title

    func testTitleFallsBackToTheFileNameWithoutItsExtension() {
        XCTAssertEqual(track(named: "01 - Opening.mp3").title, "01 - Opening")
    }

    func testExplicitTitleWins() {
        XCTAssertEqual(track(named: "01.mp3", title: "Opening").title, "Opening")
    }

    func testFileNameFallbackKeepsInteriorDots() {
        XCTAssertEqual(track(named: "a.b.c.flac").title, "a.b.c")
    }

    // MARK: - Subtitle

    func testSubtitleCombinesArtistAndAlbum() {
        XCTAssertEqual(track(artist: "Boards", album: "Music").subtitle, "Boards — Music")
    }

    func testSubtitleUsesArtistAloneWhenAlbumIsUnknown() {
        XCTAssertEqual(track(artist: "Boards").subtitle, "Boards")
    }

    func testSubtitleUsesAlbumAloneWhenArtistIsUnknown() {
        XCTAssertEqual(track(album: "Music").subtitle, "Music")
    }

    func testSubtitleIsNilWhenNeitherIsKnown() {
        XCTAssertNil(track().subtitle)
    }

    // MARK: - Identity

    /// Rows are identified by `id`, so two entries for the same file must stay
    /// distinct — the playlist is allowed to contain a track more than once.
    func testTracksForTheSameFileAreDistinct() {
        let url = URL(fileURLWithPath: "/music/song.mp3")

        XCTAssertNotEqual(Track(url: url), Track(url: url))
    }

    func testACopyKeepsItsIdentity() {
        var original = Track(url: URL(fileURLWithPath: "/music/song.mp3"))
        let id = original.id
        original.title = "Renamed"

        XCTAssertEqual(original.id, id)
    }
}
