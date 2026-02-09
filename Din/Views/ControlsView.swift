import SwiftUI
import UniformTypeIdentifiers

struct ControlsView: View {
    @ObservedObject var manager: PlaylistManager
    @State private var isDropTargeted = false
    @State private var showVolumePopover = false

    var body: some View {
        VStack(spacing: 6) {
            // Now playing info — fixed height so controls don't shift
            VStack(alignment: .leading, spacing: 1) {
                Text(manager.currentTrack?.title ?? "Din")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Group {
                    if let subtitle = manager.currentTrack?.subtitle {
                        Text(subtitle)
                    } else {
                        Text(" ")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Transport controls (centered) + volume (right)
            ZStack {
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
                }

                HStack {
                    Spacer()
                    Button {
                        showVolumePopover.toggle()
                    } label: {
                        Image(systemName: volumeIconName)
                            .font(.system(size: 12))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showVolumePopover, arrowEdge: .bottom) {
                        Slider(
                            value: Binding(
                                get: { manager.volume },
                                set: { manager.setVolume($0) }
                            ), in: Float(0)...Float(1)
                        )
                        .frame(width: 100)
                        .padding(8)
                    }
                }
            }

            // Progress bar — TimelineView drives updates without triggering @Published changes
            TimelineView(.animation(minimumInterval: 0.1, paused: !manager.isPlaying)) { _ in
                ProgressBar(
                    currentTime: manager.displayTime,
                    duration: manager.currentTrack?.duration ?? 0,
                    onSeek: manager.seek
                )
            }
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

    private var volumeIconName: String {
        if manager.volume <= 0 { return "speaker.slash.fill" }
        if manager.volume < 0.33 { return "speaker.wave.1.fill" }
        if manager.volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
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
