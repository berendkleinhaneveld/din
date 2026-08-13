import AVFoundation
import Foundation

/// Synthesizes audio files at test time so no binary fixtures need to live in the repo.
enum AudioFixture {
    enum FixtureError: Error {
        case formatUnavailable
        case bufferUnavailable
    }

    static let sampleRate: Double = 44100

    /// Write a mono file that sits at `quiet` amplitude throughout, except for short
    /// full-scale bursts starting at the given fractions of its duration.
    ///
    /// Peak extraction normalizes against the loudest sample, so a burst at a known
    /// position gives an exact expectation for where it must land in the output.
    @discardableResult
    static func writeBursts(
        to url: URL,
        seconds: Double = 20,
        burstsAt fractions: [Double],
        burstSeconds: Double = 0.1,
        quiet: Float = 0.1
    ) throws -> Int {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw FixtureError.formatUnavailable
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)

        let totalFrames = Int(seconds * sampleRate)
        let burstFrames = Int(burstSeconds * sampleRate)
        let burstStarts = fractions.map { Int(Double(totalFrames) * $0) }

        // Written in slices so the fixture itself never holds the whole file in memory.
        let sliceFrames = Int(sampleRate)
        var written = 0

        while written < totalFrames {
            let count = min(sliceFrames, totalFrames - written)
            guard
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                let samples = buffer.floatChannelData?[0]
            else {
                throw FixtureError.bufferUnavailable
            }
            buffer.frameLength = AVAudioFrameCount(count)

            for offset in 0..<count {
                let frame = written + offset
                let inBurst = burstStarts.contains { frame >= $0 && frame < $0 + burstFrames }
                samples[offset] = inBurst ? 1.0 : quiet
            }

            try file.write(from: buffer)
            written += count
        }

        return totalFrames
    }

    /// A unique path in a fresh temporary directory, removed by `cleanUp`.
    static func temporaryURL(extension ext: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("din-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("fixture.\(ext)")
    }

    static func cleanUp(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
