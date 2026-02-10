import SwiftUI

/// A SoundCloud-style waveform progress bar rendered via Canvas.
/// Displays vertical bars mirrored around a center line, with played/unplayed coloring.
/// Supports tap-to-seek and drag-to-seek.
struct WaveformView: View {
    let peaks: [Float]
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var isDragging = false
    @State private var dragProgress: Double = 0

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return isDragging ? dragProgress : currentTime / duration
    }

    private let barWidth: CGFloat = 2
    private let barGap: CGFloat = 1
    private let barCornerRadius: CGFloat = 1
    private let viewHeight: CGFloat = 50

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                let width = geo.size.width
                Canvas { context, size in
                    drawWaveform(context: context, size: size)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            dragProgress = min(max(0, value.location.x / width), 1)
                        }
                        .onEnded { value in
                            let finalProgress = min(max(0, value.location.x / width), 1)
                            onSeek(finalProgress * duration)
                            isDragging = false
                        }
                )
            }
            .frame(height: viewHeight)

            // Time labels
            HStack {
                Text(formatTime(isDragging ? dragProgress * duration : currentTime))
                    .monospacedDigit()
                Spacer()
                Text(formatTime(duration))
                    .monospacedDigit()
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Drawing

    private func drawWaveform(context: GraphicsContext, size: CGSize) {
        let totalBarWidth = barWidth + barGap
        let barCount = max(1, Int(size.width / totalBarWidth))
        let midY = size.height / 2
        let maxBarHeight = midY - 1

        let playedColor = Color.accentColor
        let unplayedColor = Color.white.opacity(0.25)
        let playheadX = size.width * progress

        for i in 0..<barCount {
            let peakIndex = peaks.isEmpty ? 0 : (i * peaks.count) / barCount
            let peak: Float = peaks.isEmpty ? 0 : peaks[min(peakIndex, peaks.count - 1)]
            let amplitude = CGFloat(max(peak, 0.03))
            let halfHeight = amplitude * maxBarHeight

            let x = CGFloat(i) * totalBarWidth
            let barRect = CGRect(
                x: x,
                y: midY - halfHeight,
                width: barWidth,
                height: halfHeight * 2
            )
            let roundedBar = RoundedRectangle(cornerRadius: barCornerRadius)
                .path(in: barRect)

            let color = x < playheadX ? playedColor : unplayedColor
            context.fill(roundedBar, with: .color(color))
        }

        // Draw playhead line
        if duration > 0 {
            let lineRect = CGRect(x: playheadX - 0.5, y: 0, width: 1, height: size.height)
            context.fill(Rectangle().path(in: lineRect), with: .color(.white.opacity(0.6)))
        }
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}
