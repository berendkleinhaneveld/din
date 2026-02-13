import SwiftUI

/// A waveform progress bar rendered via Canvas.
/// Displays vertical bars growing upward from the bottom with played/unplayed coloring.
/// Supports tap-to-seek, drag-to-seek, hover preview, and animated bar transitions.
struct WaveformView: View {
    let peaks: [Float]
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void
    let now: Date

    @Environment(\.colorScheme) private var colorScheme

    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var hoverProgress: Double?
    @State private var viewWidth: CGFloat = 1

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
    private let barCornerRadius: CGFloat = 0
    private let viewHeight: CGFloat = 32

    var body: some View {
        VStack(spacing: 2) {
            Canvas { context, size in
                drawWaveform(context: context, size: size)
            }
            .frame(height: viewHeight)
            .contentShape(Rectangle())
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { viewWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, new in viewWidth = new }
                }
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        dragProgress = min(max(0, value.location.x / viewWidth), 1)
                    }
                    .onEnded { value in
                        let finalProgress = min(max(0, value.location.x / viewWidth), 1)
                        onSeek(finalProgress * duration)
                        isDragging = false
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverProgress = min(max(0, location.x / viewWidth), 1)
                case .ended:
                    hoverProgress = nil
                }
            }
            .onAppear {
                // If peaks are already loaded (e.g. from cache at startup),
                // animate them in from zero once the window is visible.
                if !peaks.isEmpty {
                    fromPeaks = Array(repeating: 0, count: peaks.count)
                    transitionStart = Date()
                }
            }
            .onChange(of: peaks) { oldValue, newValue in
                // Compute what's currently displayed and use as the starting point
                if let start = transitionStart {
                    let elapsed = Float(now.timeIntervalSince(start))
                    let t = easeOut(min(1, elapsed / Float(transitionDuration)))
                    fromPeaks = interpolatePeaks(from: fromPeaks, to: oldValue, t: t)
                } else if oldValue.isEmpty && !newValue.isEmpty {
                    // First load — animate from zero
                    fromPeaks = Array(repeating: 0, count: newValue.count)
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
            let elapsed = Float(now.timeIntervalSince(start))
            animT = easeOut(min(1, elapsed / Float(transitionDuration)))
        } else {
            animT = 1
        }

        let totalBarWidth = barWidth + barGap
        let barCount = max(1, Int(size.width / totalBarWidth))
        let maxBarHeight = size.height - 1

        let playedColor = Color.accentColor
        let playedLightColor = Color.accentColor.opacity(0.45)
        let unplayedColor = colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.25)
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
                let playheadBinIndex = min(Int(progress * Double(barCount)), barCount - 1)
                if i < playheadBinIndex {
                    color = playedColor
                } else if i > playheadBinIndex {
                    color = unplayedColor
                } else {
                    let binFraction = (progress * Double(barCount)) - Double(playheadBinIndex)
                    color = blend(unplayedColor, playedColor, fraction: binFraction)
                }
            }

            context.fill(roundedBar, with: .color(color))
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

    /// Linearly interpolate between two colors.
    private func blend(_ c1: Color, _ c2: Color, fraction: Double) -> Color {
        let f = min(max(fraction, 0), 1)
        let r1 = NSColor(c1).usingColorSpace(.sRGB) ?? NSColor(c1)
        let r2 = NSColor(c2).usingColorSpace(.sRGB) ?? NSColor(c2)
        var r1r: CGFloat = 0
        var r1g: CGFloat = 0
        var r1b: CGFloat = 0
        var r1a: CGFloat = 0
        var r2r: CGFloat = 0
        var r2g: CGFloat = 0
        var r2b: CGFloat = 0
        var r2a: CGFloat = 0
        r1.getRed(&r1r, green: &r1g, blue: &r1b, alpha: &r1a)
        r2.getRed(&r2r, green: &r2g, blue: &r2b, alpha: &r2a)
        return Color(
            red: r1r + (r2r - r1r) * f,
            green: r1g + (r2g - r1g) * f,
            blue: r1b + (r2b - r1b) * f,
            opacity: r1a + (r2a - r1a) * f
        )
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}
