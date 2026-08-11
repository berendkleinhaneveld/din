import SwiftUI
import UniformTypeIdentifiers

struct ControlsView: View {
    @ObservedObject var manager: PlaylistManager
    @State private var isDropTargeted = false
    @State private var showVolumePopover = false

    /// Drives the waveform's bar-transition animation: bumped whenever new peaks
    /// arrive, and cleared once they stop changing.
    @State private var peaksVersion = 0
    @State private var waveformIsSettled = true

    /// Redraw the waveform Canvas at 30 fps only when something is actually
    /// moving. Ticking unconditionally kept redrawing an unchanging waveform
    /// 30 times a second for as long as the app stayed open, even while paused
    /// with nothing loaded.
    private var tickInterval: TimeInterval {
        manager.isPlaying || !waveformIsSettled ? 1.0 / 30.0 : 1.0
    }

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
                            .frame(width: 24, height: 24)
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

            // Waveform progress bar — pass context.date so the Canvas
            // redraws each tick (SwiftUI skips redraws when no props change)
            TimelineView(.periodic(from: .now, by: tickInterval)) { context in
                WaveformView(
                    peaks: manager.waveformPeaks,
                    currentTime: manager.displayTime,
                    duration: manager.currentTrack?.duration ?? 0,
                    onSeek: manager.seek,
                    now: context.date
                )
            }
            .onChange(of: manager.waveformPeaks) { _, _ in
                waveformIsSettled = false
                peaksVersion &+= 1
            }
            .task(id: peaksVersion) {
                guard !waveformIsSettled else { return }
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                waveformIsSettled = true
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
        DropLoader.loadURLs(from: providers) { urls in
            manager.replacePlaylist(urls: urls)
        }
    }
}
