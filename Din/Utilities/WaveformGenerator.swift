import AVFoundation
import Foundation

/// Decodes audio files, extracts peak amplitudes, and caches the results to disk.
actor WaveformGenerator {
    static let shared = WaveformGenerator()

    enum GeneratorError: Error {
        case unsupportedFormat
        case allocationFailed
    }

    private let binCount = 2048

    /// Frames decoded per read. Peak memory is bounded by this rather than by the
    /// length of the file: a whole-file float32 buffer is roughly 21 MB per minute
    /// of 44.1 kHz stereo, so an hour-long recording needs well over a gigabyte in
    /// one allocation — which is both wasteful and liable to fail outright.
    private static let framesPerRead: AVAudioFrameCount = 1 << 18  // ~6 s at 44.1 kHz

    private let cacheDirectory: URL

    /// - Parameter cacheDirectory: where generated peaks are cached. Defaults to a
    ///   folder in the user's caches directory; tests pass a temporary one so a test
    ///   run never reads or writes the cache the app itself uses.
    init(cacheDirectory: URL? = nil) {
        self.cacheDirectory = cacheDirectory ?? Self.defaultCacheDirectory
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }

    private static var defaultCacheDirectory: URL {
        // Falling back to the temporary directory keeps a missing caches directory
        // from taking the app down on launch.
        let caches =
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("din-waveforms", isDirectory: true)
    }

    // MARK: - Public API

    /// Generate or load cached waveform peaks for the given audio file.
    ///
    /// Returns an array of `binCount` floats in 0.0–1.0, calling `onProgress` on
    /// the main actor as each chunk is decoded — or once with the full result when
    /// the peaks come from the cache.
    ///
    /// Cancellation is the caller's: cancelling the enclosing task stops the decode
    /// (see `decode`). `PlaylistManager` holds the task for the current track and
    /// cancels it when the track changes.
    func peaksStreaming(
        for url: URL,
        onProgress: @escaping @MainActor @Sendable ([Float]) -> Void
    ) async throws -> [Float] {
        if let cached = loadCache(for: url) {
            await onProgress(cached)
            return cached
        }

        let peaks = try await decode(url: url, onProgress: onProgress)
        saveCache(peaks, for: url)
        return peaks
    }

    // MARK: - Decode & Extract

    /// Decode `url` on a background queue, reporting partial results as they land.
    ///
    /// The work runs on a DispatchQueue rather than the cooperative pool so a long
    /// decode can't starve it and stall the UI. `withCheckedThrowingContinuation`
    /// has no cancellation of its own, so a flag is handed to the worker and
    /// flipped by the enclosing cancellation handler.
    private func decode(
        url: URL,
        onProgress: @escaping @MainActor @Sendable ([Float]) -> Void
    ) async throws -> [Float] {
        let binCount = self.binCount
        let cancelFlag = CancelFlag()

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Float], Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let peaks = try Self.extractPeaks(
                            url: url,
                            binCount: binCount,
                            isCancelled: { cancelFlag.isCancelled },
                            onProgress: { partial in
                                DispatchQueue.main.async {
                                    MainActor.assumeIsolated { onProgress(partial) }
                                }
                            }
                        )
                        continuation.resume(returning: peaks)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancelFlag.cancel()
        }
    }

    /// Read the file in fixed-size chunks, folding each chunk into the peak bins.
    ///
    /// Bins can straddle chunk boundaries, so a partially filled bin is carried
    /// over by seeding the running maximum from what is already stored.
    private static func extractPeaks(
        url: URL,
        binCount: Int,
        isCancelled: () -> Bool,
        onProgress: ([Float]) -> Void
    ) throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: url)
        let processingFormat = audioFile.processingFormat
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: processingFormat.sampleRate,
                channels: processingFormat.channelCount,
                interleaved: false
            )
        else {
            throw GeneratorError.unsupportedFormat
        }

        let totalFrames = audioFile.length
        guard totalFrames > 0 else { return Array(repeating: 0, count: binCount) }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesPerRead) else {
            throw GeneratorError.allocationFailed
        }

        let framesPerBin = max(1, Int(totalFrames / Int64(binCount)))
        let channelCount = Int(format.channelCount)
        var peaks = [Float](repeating: 0, count: binCount)
        var globalMax: Float = 0
        var frameCursor = 0
        var publishedBin = -1

        while frameCursor < Int(totalFrames) {
            if isCancelled() { throw CancellationError() }

            try audioFile.read(into: buffer, frameCount: framesPerRead)
            let framesRead = Int(buffer.frameLength)
            guard framesRead > 0 else { break }

            let chunkEnd = frameCursor + framesRead
            var bin = frameCursor / framesPerBin

            while bin < binCount {
                let binStart = bin * framesPerBin
                if binStart >= chunkEnd { break }

                let binEnd = min(binStart + framesPerBin, chunkEnd)
                let localStart = max(binStart, frameCursor) - frameCursor
                let localEnd = binEnd - frameCursor
                guard localStart < localEnd else {
                    bin += 1
                    continue
                }

                var maxVal = peaks[bin]
                for channel in 0..<channelCount {
                    guard let channelData = buffer.floatChannelData?[channel] else { continue }
                    for frame in localStart..<localEnd {
                        let absVal = abs(channelData[frame])
                        if absVal > maxVal { maxVal = absVal }
                    }
                }
                peaks[bin] = maxVal
                if maxVal > globalMax { globalMax = maxVal }
                bin += 1
            }

            frameCursor = chunkEnd

            // Publish a normalized snapshot as bins complete.
            let completedBin = min(frameCursor / framesPerBin, binCount)
            if completedBin > publishedBin {
                publishedBin = completedBin
                onProgress(normalized(peaks, by: globalMax))
            }
        }

        return normalized(peaks, by: globalMax)
    }

    private static func normalized(_ peaks: [Float], by globalMax: Float) -> [Float] {
        guard globalMax > 0 else { return peaks }
        return peaks.map { $0 / globalMax }
    }

    // MARK: - Cache

    private func cacheKey(for url: URL) -> String {
        let path = url.path
        let modified: String
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
            let date = attrs[.modificationDate] as? Date
        {
            modified = String(Int(date.timeIntervalSince1970))
        } else {
            modified = "0"
        }
        let combined = "\(path)|\(modified)"
        var hash: UInt64 = 5381
        for byte in combined.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    private func cacheURL(for url: URL) -> URL {
        cacheDirectory.appendingPathComponent(cacheKey(for: url) + ".waveform")
    }

    private func loadCache(for url: URL) -> [Float]? {
        let path = cacheURL(for: url)
        guard let data = try? Data(contentsOf: path) else { return nil }
        let size = MemoryLayout<Float>.size
        guard data.count == binCount * size else { return nil }
        // `Data` gives no alignment guarantee, so read each value unaligned
        // rather than binding the raw buffer to `Float`.
        return data.withUnsafeBytes { raw in
            (0..<binCount).map { raw.loadUnaligned(fromByteOffset: $0 * size, as: Float.self) }
        }
    }

    private func saveCache(_ peaks: [Float], for url: URL) {
        let path = cacheURL(for: url)
        let data = peaks.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        try? data.write(to: path, options: .atomic)
    }
}

/// Cancellation signal that can cross into the decode worker queue.
private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
    }
}
