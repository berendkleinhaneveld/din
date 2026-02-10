import AVFoundation
import Foundation

/// Decodes audio files, extracts peak amplitudes, and caches the results to disk.
actor WaveformGenerator {
    static let shared = WaveformGenerator()

    private let binCount = 2048
    private let cacheDirectory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("din-waveforms", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Currently running generation tasks, keyed by file URL. Used for cancellation.
    private var inFlightTasks: [URL: Task<[Float], Error>] = [:]

    // MARK: - Public API

    /// Generate or load cached waveform peaks for the given audio file.
    /// Returns an array of `binCount` floats in 0.0–1.0.
    func peaks(for url: URL) async throws -> [Float] {
        cancelAll(except: url)

        if let cached = loadCache(for: url) {
            return cached
        }

        if let existing = inFlightTasks[url] {
            return try await existing.value
        }

        let task = Task<[Float], Error> {
            let peaks = try await decodeAndExtract(url: url)
            saveCache(peaks, for: url)
            return peaks
        }

        inFlightTasks[url] = task

        do {
            let result = try await task.value
            inFlightTasks[url] = nil
            return result
        } catch {
            inFlightTasks[url] = nil
            throw error
        }
    }

    /// Generate waveform peaks with streaming progress updates.
    /// Calls `onProgress` on the main actor after each chunk is decoded.
    /// If cached, calls `onProgress` once with the full result.
    func peaksStreaming(
        for url: URL,
        onProgress: @MainActor @Sendable ([Float]) -> Void
    ) async throws -> [Float] {
        cancelAll(except: url)

        if let cached = loadCache(for: url) {
            await onProgress(cached)
            return cached
        }

        let peaks = try await decodeAndExtractStreaming(url: url, onProgress: onProgress)
        saveCache(peaks, for: url)
        return peaks
    }

    /// Pre-generate and cache waveform for a URL without returning the result.
    /// Does nothing if already cached or in-flight.
    func prefetch(url: URL) async {
        if loadCache(for: url) != nil { return }
        if inFlightTasks[url] != nil { return }

        let task = Task<[Float], Error> {
            let peaks = try await decodeAndExtract(url: url)
            saveCache(peaks, for: url)
            return peaks
        }
        inFlightTasks[url] = task
        _ = try? await task.value
        inFlightTasks[url] = nil
    }

    /// Cancel all in-flight generation tasks except for the given URL.
    func cancelAll(except keepURL: URL? = nil) {
        for (url, task) in inFlightTasks where url != keepURL {
            task.cancel()
            inFlightTasks[url] = nil
        }
    }

    // MARK: - Decode & Extract

    private func decodeAndExtract(url: URL) async throws -> [Float] {
        try Task.checkCancellation()

        let audioFile = try AVAudioFile(forReading: url)
        let processingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: audioFile.processingFormat.sampleRate,
            channels: audioFile.processingFormat.channelCount,
            interleaved: false
        )!

        let frameCount = AVAudioFrameCount(audioFile.length)
        guard frameCount > 0 else { return Array(repeating: 0, count: binCount) }

        let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: frameCount)!
        try audioFile.read(into: buffer)

        try Task.checkCancellation()

        return extractPeaks(from: buffer)
    }

    private func decodeAndExtractStreaming(
        url: URL,
        onProgress: @MainActor @Sendable ([Float]) -> Void
    ) async throws -> [Float] {
        try Task.checkCancellation()

        let audioFile = try AVAudioFile(forReading: url)
        let processingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: audioFile.processingFormat.sampleRate,
            channels: audioFile.processingFormat.channelCount,
            interleaved: false
        )!

        let totalFrames = Int(audioFile.length)
        guard totalFrames > 0 else { return Array(repeating: 0, count: binCount) }

        let channelCount = Int(processingFormat.channelCount)
        let framesPerBin = max(1, totalFrames / binCount)
        var rawPeaks = [Float](repeating: 0, count: binCount)
        var globalMax: Float = 0

        // Read in chunks — 16 chunks gives frequent progress updates
        let chunkCount = 16
        let framesPerChunk = max(1, totalFrames / chunkCount)

        var framesRead = 0
        let chunkBuffer = AVAudioPCMBuffer(
            pcmFormat: processingFormat,
            frameCapacity: AVAudioFrameCount(framesPerChunk)
        )!

        for chunkIndex in 0..<chunkCount {
            try Task.checkCancellation()

            let remaining = totalFrames - framesRead
            guard remaining > 0 else { break }

            let framesToRead = min(framesPerChunk, remaining)
            chunkBuffer.frameLength = 0
            try audioFile.read(into: chunkBuffer, frameCount: AVAudioFrameCount(framesToRead))

            let actualFramesRead = Int(chunkBuffer.frameLength)
            guard actualFramesRead > 0 else { break }

            // Compute peaks for bins covered by this chunk
            for frame in 0..<actualFramesRead {
                let globalFrame = framesRead + frame
                let bin = min(globalFrame / framesPerBin, binCount - 1)

                for ch in 0..<channelCount {
                    guard let channelData = chunkBuffer.floatChannelData?[ch] else { continue }
                    let absVal = abs(channelData[frame])
                    if absVal > rawPeaks[bin] {
                        rawPeaks[bin] = absVal
                        if absVal > globalMax { globalMax = absVal }
                    }
                }
            }

            framesRead += actualFramesRead

            // Publish normalized partial result
            if globalMax > 0 {
                let normalized = rawPeaks.map { $0 / globalMax }
                await onProgress(normalized)
            } else {
                await onProgress(rawPeaks)
            }

            // Yield to let other tasks run
            if chunkIndex < chunkCount - 1 {
                await Task.yield()
            }
        }

        // Final normalization
        if globalMax > 0 {
            for i in 0..<rawPeaks.count {
                rawPeaks[i] /= globalMax
            }
        }

        return rawPeaks
    }

    private func extractPeaks(from buffer: AVAudioPCMBuffer) -> [Float] {
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0 else { return Array(repeating: 0, count: binCount) }

        let framesPerBin = max(1, frameCount / binCount)
        var peaks = [Float](repeating: 0, count: binCount)

        for bin in 0..<binCount {
            let start = bin * framesPerBin
            let end = min(start + framesPerBin, frameCount)
            guard start < end else { continue }

            var maxVal: Float = 0
            for ch in 0..<channelCount {
                guard let channelData = buffer.floatChannelData?[ch] else { continue }
                for frame in start..<end {
                    let absVal = abs(channelData[frame])
                    if absVal > maxVal { maxVal = absVal }
                }
            }
            peaks[bin] = maxVal
        }

        // Normalize to 0.0–1.0
        let globalMax = peaks.max() ?? 0
        if globalMax > 0 {
            for i in 0..<peaks.count {
                peaks[i] /= globalMax
            }
        }

        return peaks
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
        let expectedSize = binCount * MemoryLayout<Float>.size
        guard data.count == expectedSize else { return nil }
        return data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
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
