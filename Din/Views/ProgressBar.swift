import SwiftUI

struct ProgressBar: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var isDragging = false
    @State private var dragProgress: Double = 0

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return isDragging ? dragProgress : currentTime / duration
    }

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    // Track background
                    Capsule()
                        .fill(.white.opacity(0.15))
                        .frame(height: 4)

                    // Filled portion
                    Capsule()
                        .fill(.white.opacity(0.8))
                        .frame(width: max(0, width * progress), height: 4)

                    // Thumb
                    Circle()
                        .fill(.white)
                        .frame(width: 10, height: 10)
                        .offset(x: max(0, width * progress - 5))
                        .opacity(isDragging ? 1 : 0)
                }
                .frame(height: 10)
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
            .frame(height: 10)

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

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}
