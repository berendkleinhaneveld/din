import SwiftUI

struct ContentView: View {
    @ObservedObject var manager: PlaylistManager

    var body: some View {
        VStack(spacing: 0) {
            ControlsView(manager: manager)

            // Status bar
            HStack(spacing: 8) {
                Button(action: manager.toggleRepeat) {
                    Image(systemName: "repeat")
                        .font(.system(size: 11))
                        .foregroundStyle(manager.repeatEnabled ? .primary : .tertiary)
                }
                .buttonStyle(.plain)
                .help(manager.repeatEnabled ? "Repeat On" : "Repeat Off")

                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

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
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Divider()

            PlaylistView(manager: manager)
        }
        .background(.ultraThinMaterial)
        .frame(minWidth: 300, idealWidth: 320, minHeight: 400, idealHeight: 500)
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
