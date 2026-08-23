import SwiftUI

/// The window's two shapes, composed here rather than in two separate views on purpose.
///
/// The now-playing block — title, transport, waveform — is the *same* `ControlsView` in both, at
/// the same position in this `VStack`, with only the things around it appearing and disappearing.
/// Structural position is what SwiftUI keys view identity on, so this is what lets the block keep
/// its state across the collapse. Put the two modes in an `if`/`else` and it is a different view
/// each time: the waveform's bars drop to zero and grow back on every switch, because
/// `WaveformView.onAppear` quite reasonably assumes a fresh appearance means fresh peaks.
struct ContentView: View {
    @ObservedObject var manager: PlaylistManager
    @ObservedObject private var coverWindow = CoverWindowController.shared

    @State private var isHovering = false
    @FocusState private var focus: PlayerControl?

    /// Poses the view for previews and offscreen captures, which have no window to collapse and no
    /// pointer to hover with. Mirrors `PlaylistManager.poseForScreenshot`: it exists only so the
    /// view can be looked at.
    enum Pose {
        case cover
        case coverAtRest
    }

    #if DEBUG
        var pose: Pose?
    #endif

    private var isCoverMode: Bool {
        #if DEBUG
            if pose != nil { return true }
        #endif
        return coverWindow.isCoverMode
    }

    /// Whether the cover's overlay is showing: pointer-over, or focus-within so it is reachable by
    /// keyboard rather than only by mouse.
    private var isRevealed: Bool {
        guard isCoverMode else { return true }
        #if DEBUG
            if pose == .cover { return true }
            if pose == .coverAtRest { return false }
        #endif
        return isHovering || focus != nil
    }

    var body: some View {
        ZStack(alignment: .top) {
            if isCoverMode {
                CoverBackdrop(manager: manager, isRevealed: isRevealed, focus: $focus)
            }

            VStack(spacing: 0) {
                // In cover mode the block sits at the foot of the artwork. A sibling appearing
                // above it does not disturb it — only moving it to a different slot would.
                if isCoverMode {
                    Spacer(minLength: 0)
                }

                ControlsView(
                    manager: manager,
                    overArtwork: isCoverMode,
                    isRevealed: isRevealed,
                    focus: $focus
                )

                if !isCoverMode {
                    statusBar
                    Divider()
                    PlaylistView(manager: manager)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(.ultraThinMaterial)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.17), value: isRevealed)
        // The cover's clamps are on the width alone. A minimum height would arrive at the window as
        // a *content* minimum and come back out inflated by the titlebar's height, which is enough
        // to stop the square being square at the bottom clamp; the 1:1 aspect
        // `CoverWindowController` locks carries these over to the height anyway.
        .frame(
            minWidth: isCoverMode ? CoverWindowController.minSide : 300,
            idealWidth: isCoverMode ? nil : 320,
            maxWidth: isCoverMode ? CoverWindowController.maxSide : nil,
            minHeight: isCoverMode ? nil : 400,
            idealHeight: isCoverMode ? nil : 500
        )
        // Outermost, and after the frame: `.hiddenTitleBar` still insets its content by the
        // titlebar's height, and the cover wants none of it — artwork edge to edge. Applied inside
        // the frame instead, the expansion lands on the wrong view and the block's own padding
        // ends up outside the window.
        .ignoresSafeArea(.container, edges: isCoverMode ? .top : [])
    }

    private var statusBar: some View {
        ZStack {
            Text(statusText)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            HStack {
                Button(action: manager.toggleRepeat) {
                    Image(systemName: "repeat")
                        .font(.system(size: 11))
                        .foregroundStyle(manager.repeatEnabled ? .primary : .tertiary)
                }
                .buttonStyle(.plain)
                .help(manager.repeatEnabled ? "Repeat On" : "Repeat Off")

                Spacer()

                Button(action: manager.clearPlaylist) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear Playlist")
                .disabled(!manager.hasContent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var statusText: String {
        let count = manager.tracks.count
        guard count > 0 else { return "" }
        let label = count == 1 ? "1 track" : "\(count) tracks"
        let total = manager.totalDuration
        guard total > 0, total.isFinite else { return label }
        return "\(label), \(formatTotalTime(total))"
    }

    private func formatTotalTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        }
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}
