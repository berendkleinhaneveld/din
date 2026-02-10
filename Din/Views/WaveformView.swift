import SwiftUI

/// A waveform progress bar rendered via Canvas.
/// Displays vertical bars growing upward from the bottom with played/unplayed coloring.
/// Supports tap-to-seek, drag-to-seek, hover preview, and animated bar transitions.
struct WaveformView: View {
    let peaks: [Float]
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var hoverProgress: Double?

    // Animation state — bars interpolate from fromPeaks to peaks
    @State private var fromPeaks: [Float] = []
    @State private var transitionStart: Date?
    private let transitionDuration: TimeInterval = 0.35

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return isDragging ? dragProgress : currentTime / duration
    }

    private let barWidth: CGFloat = 2
    private let barGap: CGFloat = 1
    private let barCornerRadius: CGFloat = 1
    private let viewHeight: CGFloat = 32

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
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hoverProgress = min(max(0, location.x / width), 1)
                    case .ended:
                        hoverProgress = nil
                    }
                }
            }
            .frame(height: viewHeight)
            .onChange(of: peaks) { oldValue, newValue in
                // Compute what's currently displayed and use as the starting point
                if let start = transitionStart {
                    let elapsed = Float(Date().timeIntervalSince(start))
                    let t = easeOut(min(1, elapsed / Float(transitionDuration)))
                    fromPeaks = interpolatePeaks(from: fromPeaks, to: oldValue, t: t)
                } else {
                    fromPeaks = oldValue
                }
                transitionStart = Date()
            }

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

    // MARK: - Animation Helpers

    private func easeOut(_ t: Float) -> Float {
        1 - pow(1 - t, 3)
    }

    private func interpolatePeaks(from: [Float], to: [Float], t: Float) -> [Float] {
        let count = max(from.count, to.count)
        guard count > 0 else { return [] }
        return (0..<count).map { i in
            let f = i < from.count ? from[i] : 0
            let target = i < to.count ? to[i] : 0
            return f + (target - f) * t
        }
    }

    // MARK: - Drawing

    private func drawWaveform(context: GraphicsContext, size: CGSize) {
        // Compute animation progress
        let animT: Float
        if let start = transitionStart {
            let elapsed = Float(Date().timeIntervalSince(start))
            animT = easeOut(min(1, elapsed / Float(transitionDuration)))
        } else {
            animT = 1
        }

        let totalBarWidth = barWidth + barGap
        let barCount = max(1, Int(size.width / totalBarWidth))
        let maxBarHeight = size.height - 1

        let playedColor = Color.accentColor
        let playedLightColor = Color.accentColor.opacity(0.45)
        let unplayedColor = Color.white.opacity(0.25)
        let playheadX = size.width * progress
        let hoverX = hoverProgress.map { size.width * $0 }

        for i in 0..<barCount {
            let peakIndex = peaks.isEmpty ? 0 : (i * peaks.count) / barCount
            let clampedIndex = peaks.isEmpty ? 0 : min(peakIndex, peaks.count - 1)

            let targetPeak: Float = peaks.isEmpty ? 0 : peaks[clampedIndex]
            let fromPeak: Float = clampedIndex < fromPeaks.count ? fromPeaks[clampedIndex] : 0
            let peak = fromPeak + (targetPeak - fromPeak) * animT

            let amplitude = CGFloat(max(peak, 0.03))
            let barHeight = amplitude * maxBarHeight

            let x = CGFloat(i) * totalBarWidth
            let barRect = CGRect(
                x: x,
                y: size.height - barHeight,
                width: barWidth,
                height: barHeight
            )
            let roundedBar = RoundedRectangle(cornerRadius: barCornerRadius)
                .path(in: barRect)

            let color: Color
            if isDragging {
                color = x < playheadX ? playedColor : unplayedColor
            } else if let hoverX {
                color = barColor(
                    barX: x, playheadX: playheadX, hoverX: hoverX,
                    played: playedColor, playedLight: playedLightColor, unplayed: unplayedColor
                )
            } else {
                color = x < playheadX ? playedColor : unplayedColor
            }

            context.fill(roundedBar, with: .color(color))
        }

        // Draw playhead — sized to the height of the bar it sits on + 2pt
        if duration > 0 {
            // Use the same bar-to-bin mapping as the bars themselves
            let playheadBarIndex = min(Int(progress * Double(barCount)), barCount - 1)
            let playheadPeakIndex = peaks.isEmpty ? 0 : min((playheadBarIndex * peaks.count) / barCount, peaks.count - 1)
            let targetPeak: Float = peaks.isEmpty ? 0 : peaks[playheadPeakIndex]
            let fromPeak: Float = playheadPeakIndex < fromPeaks.count ? fromPeaks[playheadPeakIndex] : 0
            let peak = fromPeak + (targetPeak - fromPeak) * animT
            let amplitude = CGFloat(max(peak, 0.03))
            let playheadBarHeight = amplitude * maxBarHeight + 2

            let playheadWidth = barWidth + 2
            let playheadRect = CGRect(
                x: playheadX - playheadWidth / 2,
                y: size.height - playheadBarHeight,
                width: playheadWidth,
                height: playheadBarHeight
            )
            let playheadShape = RoundedRectangle(cornerRadius: barCornerRadius + 0.5)
                .path(in: playheadRect)
            context.fill(playheadShape, with: .color(.white.opacity(0.8)))
        }
    }

    /// Determine bar color based on hover position relative to the playhead.
    private func barColor(
        barX: CGFloat, playheadX: CGFloat, hoverX: CGFloat,
        played: Color, playedLight: Color, unplayed: Color
    ) -> Color {
        if hoverX >= playheadX {
            if barX < playheadX {
                return played
            } else if barX < hoverX {
                return playedLight
            } else {
                return unplayed
            }
        } else {
            if barX < hoverX {
                return played
            } else if barX < playheadX {
                return playedLight
            } else {
                return unplayed
            }
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
