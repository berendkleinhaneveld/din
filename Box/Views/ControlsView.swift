import SwiftUI
import UniformTypeIdentifiers

struct ControlsView: View {
    @ObservedObject var manager: PlaylistManager
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 6) {
            // Now playing info
            VStack(spacing: 1) {
                Text(manager.currentTrack?.title ?? "Box")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let subtitle = manager.currentTrack?.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Transport controls + volume
            HStack(spacing: 12) {
                Button(action: manager.previous) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .disabled(!manager.hasContent)

                Button(action: manager.togglePlayPause) {
                    Image(systemName: manager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .disabled(!manager.hasContent)

                Button(action: manager.next) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .disabled(!manager.hasContent)

                Spacer()

                Image(systemName: "speaker.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Slider(value: Binding(
                    get: { manager.volume },
                    set: { manager.setVolume($0) }
                ), in: Float(0)...Float(1))
                .frame(width: 80)
                .controlSize(.mini)
            }

            // Progress bar
            ProgressBar(
                currentTime: manager.currentTime,
                duration: manager.currentTrack?.duration ?? 0,
                onSeek: manager.seek
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.white.opacity(isDropTargeted ? 0.1 : 0))
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
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
            manager.replacePlaylist(urls: urls)
        }
    }
}
