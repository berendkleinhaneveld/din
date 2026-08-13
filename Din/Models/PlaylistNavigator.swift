import Foundation

/// Which track comes next, expressed as pure index arithmetic.
///
/// Every navigation decision in the player routes through here — the transport
/// controls, the gapless look-ahead queue, and what happens when an item finishes
/// or is removed. Keeping the rules in one place free of playback state is what
/// makes them checkable: the bugs this logic has produced (the wrong track queued
/// after a reorder, repeat not taking effect on the last track) were all
/// disagreements between copies of this arithmetic scattered across call sites.
enum PlaylistNavigator {
    /// The track following `index`, or `nil` at the end of a playlist that does
    /// not repeat — which the caller treats as "stop".
    static func indexAfter(_ index: Int, count: Int, repeats: Bool) -> Int? {
        guard count > 0, index >= 0, index < count else { return nil }
        let next = index + 1
        if next < count { return next }
        return repeats ? 0 : nil
    }

    /// The track the Previous control should select.
    ///
    /// Never `nil` for a non-empty playlist: from the first track it wraps to the
    /// last when repeating, and otherwise restarts the first track rather than
    /// running off the front.
    static func indexBefore(_ index: Int, count: Int, repeats: Bool) -> Int? {
        guard count > 0 else { return nil }
        guard index > 0 else { return repeats ? count - 1 : 0 }
        return min(index, count) - 1
    }

    /// The track to select after a removal, given the index that was playing and
    /// how many tracks remain. `nil` once the playlist is empty.
    static func indexAfterRemoval(previousIndex: Int, remainingCount: Int) -> Int? {
        guard remainingCount > 0 else { return nil }
        return min(max(previousIndex, 0), remainingCount - 1)
    }
}
