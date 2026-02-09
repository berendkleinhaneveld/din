import SwiftUI
import UniformTypeIdentifiers

struct PlaylistView: View {
    @ObservedObject var manager: PlaylistManager
    @State private var isDropTargeted = false

    var body: some View {
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
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(isDropTargeted ? 0.06 : 0))
            )
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                loadURLs(from: providers) { urls in
                    manager.addTracks(urls: urls, at: 0)
                }
                return true
            }
        } else {
            List(selection: $manager.selection) {
                ForEach(manager.tracks) { track in
                    TrackRow(
                        track: track,
                        index: rowIndex(for: track),
                        isPlaying: manager.currentIndex == rowIndex(for: track) - 1 && manager.isPlaying,
                        isCurrent: manager.currentIndex == rowIndex(for: track) - 1
                    )
                    .frame(height: 36)
                    .tag(track.id)
                    .listRowSeparator(.visible)
                    .listRowSeparatorTint(Color(nsColor: .separatorColor).opacity(0.5))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            manager.removeTracks(ids: [track.id])
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
                        }
                        if manager.selection.count > 1, manager.selection.contains(track.id) {
                            Button("Remove Selected (\(manager.selection.count))") {
                                manager.removeTracks(ids: manager.selection)
                            }
                        }
                    }
                }
                .onMove { source, destination in
                    manager.moveTrack(from: source, to: destination)
                }
                .onInsert(of: [.fileURL]) { index, providers in
                    loadURLs(from: providers) { urls in
                        manager.addTracks(urls: urls, at: index)
                    }
                }
            }
            .listStyle(.plain)
            .onDeleteCommand {
                if !manager.selection.isEmpty {
                    manager.removeTracks(ids: manager.selection)
                }
            }
        }
    }

    private func rowIndex(for track: Track) -> Int {
        (manager.tracks.firstIndex(of: track) ?? 0) + 1
    }

    private func loadURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
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
            completion(urls)
        }
    }
}

// MARK: - Track Row

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
                        .foregroundStyle(.tertiary)
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
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(height: 30, alignment: .center)

            Spacer()

            Text(formatDuration(track.duration))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.tertiary)
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
