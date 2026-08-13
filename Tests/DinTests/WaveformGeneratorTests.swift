import AVFoundation
import XCTest

@testable import Din

final class WaveformGeneratorTests: XCTestCase {
    private var cacheDirectory: URL!
    private var generator: WaveformGenerator!

    /// Each test gets its own generator with its own cache directory, so a run
    /// never touches the app's real cache and tests cannot see each other's
    /// cached results or cancel each other's in-flight work.
    override func setUpWithError() throws {
        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("din-cache-\(UUID().uuidString)", isDirectory: true)
        generator = WaveformGenerator(cacheDirectory: cacheDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    private func cachedFileCount() throws -> Int {
        let entries = try FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path)
        return entries.filter { $0.hasSuffix(".waveform") }.count
    }

    /// 20 s at 44.1 kHz spans several of the generator's read chunks, so bursts placed
    /// across the file only land in the right bins if partially-filled bins are carried
    /// over correctly from one chunk to the next.
    func testPeaksLocateBurstsAcrossReadChunkBoundaries() async throws {
        let url = AudioFixture.temporaryURL(extension: "caf")
        defer { AudioFixture.cleanUp(url) }
        let fractions = [0.25, 0.5, 0.75]
        try AudioFixture.writeBursts(to: url, seconds: 20, burstsAt: fractions)

        let peaks = try await generator.peaks(for: url)

        XCTAssertFalse(peaks.isEmpty)
        XCTAssertEqual(peaks.max() ?? 0, 1.0, accuracy: 0.001, "peaks should be normalized to the loudest sample")

        for fraction in fractions {
            XCTAssertEqual(
                loudest(in: peaks, near: fraction), 1.0, accuracy: 0.05,
                "expected a burst near \(fraction) of the file")
        }

        // A stretch between bursts stays quiet, so the checks above cannot pass
        // simply because the whole file came back at full scale.
        XCTAssertEqual(loudest(in: peaks, near: 0.4), 0.1, accuracy: 0.02)
    }

    /// The loudest peak within 1% of the given position.
    ///
    /// Bins map to frames via a floored `frameCount / binCount`, so a burst does not
    /// land at exactly `fraction * binCount` — the rounding drifts by a couple of bins
    /// over the file. The window absorbs that while still being far tighter than the
    /// displacement a chunk-boundary bug would cause.
    private func loudest(in peaks: [Float], near fraction: Double) -> Float {
        let center = Int(Double(peaks.count) * fraction)
        let window = max(4, peaks.count / 100)
        let lower = max(0, center - window)
        let upper = min(peaks.count - 1, center + window)
        return peaks[lower...upper].max() ?? 0
    }

    func testQuietSectionsKeepTheirRelativeLevel() async throws {
        let url = AudioFixture.temporaryURL(extension: "caf")
        defer { AudioFixture.cleanUp(url) }
        try AudioFixture.writeBursts(to: url, seconds: 20, burstsAt: [0.5], quiet: 0.1)

        let peaks = try await generator.peaks(for: url)

        // Normalized against the full-scale burst, the rest of the file sits at 0.1.
        let quietIndex = Int(Double(peaks.count) * 0.1)
        XCTAssertEqual(peaks[quietIndex], 0.1, accuracy: 0.02)
    }

    // MARK: - Caching

    func testPeaksAreCachedInTheConfiguredDirectory() async throws {
        let url = AudioFixture.temporaryURL(extension: "caf")
        defer { AudioFixture.cleanUp(url) }
        try AudioFixture.writeBursts(to: url, seconds: 2, burstsAt: [0.5])
        XCTAssertEqual(try cachedFileCount(), 0)

        _ = try await generator.peaks(for: url)

        XCTAssertEqual(try cachedFileCount(), 1, "generated peaks should be cached where we asked")
    }

    /// The second read comes back from the on-disk cache rather than the decoder,
    /// which exercises the save/load round trip.
    func testCachedReadMatchesGeneratedPeaks() async throws {
        let url = AudioFixture.temporaryURL(extension: "caf")
        defer { AudioFixture.cleanUp(url) }
        try AudioFixture.writeBursts(to: url, seconds: 5, burstsAt: [0.5])

        let generated = try await generator.peaks(for: url)
        let cached = try await generator.peaks(for: url)

        XCTAssertEqual(generated, cached)
        XCTAssertEqual(try cachedFileCount(), 1, "a second read should reuse the entry, not add one")
    }

    /// Cache keys include the file's modification date, so editing a file must not
    /// serve the previous waveform.
    func testRewritingTheFileProducesAFreshCacheEntry() async throws {
        let url = AudioFixture.temporaryURL(extension: "caf")
        defer { AudioFixture.cleanUp(url) }
        try AudioFixture.writeBursts(to: url, seconds: 2, burstsAt: [0.25])
        _ = try await generator.peaks(for: url)

        try FileManager.default.removeItem(at: url)
        try AudioFixture.writeBursts(to: url, seconds: 2, burstsAt: [0.75])
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
        _ = try await generator.peaks(for: url)

        XCTAssertEqual(try cachedFileCount(), 2, "a changed file should not reuse the old entry")
    }

    func testAGeneratorWithItsOwnCacheDoesNotSeeAnotherCache() async throws {
        let url = AudioFixture.temporaryURL(extension: "caf")
        defer { AudioFixture.cleanUp(url) }
        try AudioFixture.writeBursts(to: url, seconds: 2, burstsAt: [0.5])
        _ = try await generator.peaks(for: url)

        let otherDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("din-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: otherDirectory) }
        let other = WaveformGenerator(cacheDirectory: otherDirectory)
        _ = try await other.peaks(for: url)

        let entries = try FileManager.default.contentsOfDirectory(atPath: otherDirectory.path)
        XCTAssertEqual(entries.filter { $0.hasSuffix(".waveform") }.count, 1)
    }

    // MARK: - Edge cases

    func testStreamingPublishesPartialResultsAndMatchesTheFinalPeaks() async throws {
        let url = AudioFixture.temporaryURL(extension: "caf")
        defer { AudioFixture.cleanUp(url) }
        try AudioFixture.writeBursts(to: url, seconds: 20, burstsAt: [0.5])

        let collector = ProgressCollector()
        let peaks = try await generator.peaksStreaming(for: url) { partial in
            collector.record(partial)
        }

        XCTAssertGreaterThan(collector.count, 1, "a multi-chunk file should report progress more than once")
        XCTAssertEqual(collector.lastCount, peaks.count)
    }

    func testSilentFileProducesFlatPeaks() async throws {
        let url = AudioFixture.temporaryURL(extension: "caf")
        defer { AudioFixture.cleanUp(url) }
        try AudioFixture.writeBursts(to: url, seconds: 2, burstsAt: [], quiet: 0)

        let peaks = try await generator.peaks(for: url)

        XCTAssertFalse(peaks.isEmpty)
        XCTAssertEqual(peaks.max() ?? 0, 0, accuracy: 0.0001, "a silent file must not blow up normalization")
    }

    func testMissingFileThrows() async {
        let url = URL(fileURLWithPath: "/nonexistent/din-test-\(UUID().uuidString).caf")
        do {
            _ = try await generator.peaks(for: url)
            XCTFail("expected an error for a file that does not exist")
        } catch {
            // Expected.
        }
    }
}

/// Records main-actor progress callbacks for assertions on the test thread.
private final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [Int] = []

    func record(_ partial: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        counts.append(partial.count)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return counts.count
    }

    var lastCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return counts.last ?? 0
    }
}
