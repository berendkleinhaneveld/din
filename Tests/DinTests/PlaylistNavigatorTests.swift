import XCTest

@testable import Din

final class PlaylistNavigatorTests: XCTestCase {
    // MARK: - Forwards

    func testAdvancesThroughThePlaylist() {
        XCTAssertEqual(PlaylistNavigator.indexAfter(0, count: 3, repeats: false), 1)
        XCTAssertEqual(PlaylistNavigator.indexAfter(1, count: 3, repeats: false), 2)
    }

    func testStopsAtTheEndWhenNotRepeating() {
        XCTAssertNil(PlaylistNavigator.indexAfter(2, count: 3, repeats: false))
    }

    func testWrapsToTheStartWhenRepeating() {
        XCTAssertEqual(PlaylistNavigator.indexAfter(2, count: 3, repeats: true), 0)
    }

    /// A single repeating track follows itself, which is what keeps the gapless
    /// queue fed when the playlist has one entry.
    func testASingleTrackRepeatsItself() {
        XCTAssertEqual(PlaylistNavigator.indexAfter(0, count: 1, repeats: true), 0)
        XCTAssertNil(PlaylistNavigator.indexAfter(0, count: 1, repeats: false))
    }

    func testNothingFollowsATrackInAnEmptyPlaylist() {
        XCTAssertNil(PlaylistNavigator.indexAfter(0, count: 0, repeats: false))
        XCTAssertNil(PlaylistNavigator.indexAfter(0, count: 0, repeats: true))
    }

    func testOutOfRangeIndexHasNoSuccessor() {
        XCTAssertNil(PlaylistNavigator.indexAfter(5, count: 3, repeats: true))
        XCTAssertNil(PlaylistNavigator.indexAfter(-1, count: 3, repeats: true))
    }

    // MARK: - Backwards

    func testStepsBackThroughThePlaylist() {
        XCTAssertEqual(PlaylistNavigator.indexBefore(2, count: 3, repeats: false), 1)
        XCTAssertEqual(PlaylistNavigator.indexBefore(1, count: 3, repeats: false), 0)
    }

    /// Previous on the first track restarts it rather than running off the front.
    func testHoldsAtTheFirstTrackWhenNotRepeating() {
        XCTAssertEqual(PlaylistNavigator.indexBefore(0, count: 3, repeats: false), 0)
    }

    func testWrapsToTheEndWhenRepeating() {
        XCTAssertEqual(PlaylistNavigator.indexBefore(0, count: 3, repeats: true), 2)
    }

    func testNothingPrecedesATrackInAnEmptyPlaylist() {
        XCTAssertNil(PlaylistNavigator.indexBefore(0, count: 0, repeats: true))
    }

    // MARK: - Removal

    func testKeepsThePositionWhenLaterTracksAreRemoved() {
        XCTAssertEqual(PlaylistNavigator.indexAfterRemoval(previousIndex: 1, remainingCount: 5), 1)
    }

    /// Removing from the end of the playlist clamps to the new last track rather
    /// than leaving the selection past the end.
    func testClampsToTheLastRemainingTrack() {
        XCTAssertEqual(PlaylistNavigator.indexAfterRemoval(previousIndex: 7, remainingCount: 3), 2)
    }

    func testSelectsNothingWhenThePlaylistIsEmptied() {
        XCTAssertNil(PlaylistNavigator.indexAfterRemoval(previousIndex: 2, remainingCount: 0))
    }

    func testNegativePreviousIndexClampsToTheStart() {
        XCTAssertEqual(PlaylistNavigator.indexAfterRemoval(previousIndex: -1, remainingCount: 3), 0)
    }

    // MARK: - Traversal

    /// Walking a repeating playlist returns to where it started and visits every
    /// track exactly once on the way.
    func testRepeatingTraversalCyclesThroughEveryTrack() {
        let count = 4
        var index = 0
        var visited = [index]

        for _ in 0..<count {
            guard let next = PlaylistNavigator.indexAfter(index, count: count, repeats: true) else {
                return XCTFail("a repeating playlist should always have a next track")
            }
            index = next
            visited.append(index)
        }

        XCTAssertEqual(visited, [0, 1, 2, 3, 0])
    }

    func testForwardsAndBackwardsAreInverseInTheMiddleOfThePlaylist() {
        for index in 1..<4 {
            let forward = PlaylistNavigator.indexAfter(index, count: 5, repeats: false)
            XCTAssertEqual(forward.flatMap { PlaylistNavigator.indexBefore($0, count: 5, repeats: false) }, index)
        }
    }
}
