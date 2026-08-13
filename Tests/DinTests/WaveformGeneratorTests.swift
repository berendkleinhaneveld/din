import AVFoundation
import XCTest

@testable import Din

final class WaveformGeneratorTests: XCTestCase {
    /// 20 s at 44.1 kHz spans several of the generator's read chunks, so bursts placed
    /// across the file only land in the right bins if partially-filled bins are carried
    /// over correctly from one chunk to the next.
    func testPeaksLocateBurstsAcrossReadChunkBoundaries() async throws {
        let url = AudioFixture.temporaryURL(extension: "caf")
        defer { AudioFixture.cleanUp(url) }
        let fractions = [0.25, 0.5, 0.75]
        try AudioFixture.writeBursts(to: url, seconds: 20, burstsAt: fractions)

        let peaks = try await WaveformGenerator.shared.peaks(for: url)

        XCTAssertFalse(peaks.isEmpty)
        XCTAssertEqual(peaks.max() ?? 0, 1.0, accuracy: 0.001, "peaks should be normalized to the loudest sample")

        for fraction in fractions {
            let index = Int(Double(peaks.count) * fraction)
            XCTAssertEqual(peaks[index], 1.0, accuracy: 0.05, "expected a burst at \(fraction) of the file")
        }
    }

    func testQuietSectionsKeepTheirRelativeLevel() async throws {
        let url = AudioFixture.temporaryURL(extension: "caf")
        defer { AudioFixture.cleanUp(url) }
        try AudioFixture.writeBursts(to: url, seconds: 20, burstsAt: [0.5], quiet: 0.1)

        let peaks = try await WaveformGenerator.shared.peaks(for: url)

        // Normalized against the full-scale burst, the rest of the file sits at 0.1.
        let quietIndex = Int(Double(peaks.count) * 0.1)
        XCTAssertEqual(peaks[quietIndex], 0.1, accuracy: 0.02)
    }

    /// The second read comes back from the on-disk cache rather than the decoder,
    /// which exercises the save/load round trip.
    func testCachedReadMatchesGeneratedPeaks() async throws {
        let url = AudioFixture.temporaryURL(extension: "caf")
        defer { AudioFixture.cleanUp(url) }
        try AudioFixture.writeBursts(to: url, seconds: 5, burstsAt: [0.5])

        let generated = try await WaveformGenerator.shared.peaks(for: url)
        let cached = try await WaveformGenerator.shared.peaks(for: url)

        XCTAssertEqual(generated, cached)
    }

    func testStreamingPublishesPartialResultsAndMatchesTheFinalPeaks() async throws {
        let url = AudioFixture.temporaryURL(extension: "caf")
        defer { AudioFixture.cleanUp(url) }
        try AudioFixture.writeBursts(to: url, seconds: 20, burstsAt: [0.5])

        let collector = ProgressCollector()
        let peaks = try await WaveformGenerator.shared.peaksStreaming(for: url) { partial in
            collector.record(partial)
        }

        XCTAssertGreaterThan(collector.count, 1, "a multi-chunk file should report progress more than once")
        XCTAssertEqual(collector.lastCount, peaks.count)
    }

    func testSilentFileProducesFlatPeaks() async throws {
        let url = AudioFixture.temporaryURL(extension: "caf")
        defer { AudioFixture.cleanUp(url) }
        try AudioFixture.writeBursts(to: url, seconds: 2, burstsAt: [], quiet: 0)

        let peaks = try await WaveformGenerator.shared.peaks(for: url)

        XCTAssertFalse(peaks.isEmpty)
        XCTAssertEqual(peaks.max() ?? 0, 0, accuracy: 0.0001, "a silent file must not blow up normalization")
    }

    func testMissingFileThrows() async {
        let url = URL(fileURLWithPath: "/nonexistent/din-test-\(UUID().uuidString).caf")
        do {
            _ = try await WaveformGenerator.shared.peaks(for: url)
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
