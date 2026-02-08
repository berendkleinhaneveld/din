import SwiftUI
import UniformTypeIdentifiers

struct PlaylistView: View {
    @ObservedObject var manager: PlaylistManager
    @State private var selection: Set<Track.ID> = []
    @State private var isDropTargeted = false

    var body: some View {
        Group {
            if manager.tracks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("Drop audio files here")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(Array(manager.tracks.enumerated()), id: \.element.id) { index, track in
                        TrackRow(
                            track: track,
                            index: index + 1,
                            isPlaying: manager.currentIndex == index && manager.isPlaying,
                            isCurrent: manager.currentIndex == index
                        )
                        .frame(height: 36)
                        .tag(track.id)
                        .listRowSeparator(.visible)
                        .listRowSeparatorTint(Color(nsColor: .separatorColor).opacity(0.5))
                        .onTapGesture(count: 2) {
                            manager.playTrack(at: index)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                manager.removeTracks(ids: [track.id])
                                selection.remove(track.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([track.url])
                            }
                            Divider()
                            Button("Remove") {
                                manager.removeTracks(ids: [track.id])
                                selection.remove(track.id)
                            }
                            if selection.count > 1, selection.contains(track.id) {
                                Button("Remove Selected (\(selection.count))") {
                                    manager.removeTracks(ids: selection)
                                    selection.removeAll()
                                }
                            }
                        }
                    }
                    .onMove { source, destination in
                        manager.moveTrack(from: source, to: destination)
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.white.opacity(isDropTargeted ? 0.06 : 0))
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .onDeleteCommand {
            if !selection.isEmpty {
                manager.removeTracks(ids: selection)
                selection.removeAll()
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                defer { group.leave() }
                if let data = data as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
        }
        group.notify(queue: .main) {
            manager.addTracks(urls: urls)
        }
    }
}

private struct TrackRow: View {
    let track: Track
    let index: Int
    let isPlaying: Bool
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text("\(index)")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 22, alignment: .trailing)
            .font(.system(size: 11).monospacedDigit())

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                if let subtitle = track.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(height: 30, alignment: .center)

            Spacer()

            Text(formatDuration(track.duration))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        guard duration > 0, duration.isFinite else { return "" }
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}
