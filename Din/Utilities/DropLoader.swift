import Foundation
import UniformTypeIdentifiers

/// Collects file URLs from drag-and-drop item providers.
enum DropLoader {
    /// Load file URLs from drag-and-drop providers, preserving the order they
    /// were dropped in and calling `completion` on the main queue.
    ///
    /// `loadItem` invokes its completion on an arbitrary queue, and one provider
    /// per dropped file means several of them run concurrently — so results are
    /// written into a lock-guarded, pre-sized slot array rather than appended to
    /// a shared array from multiple threads.
    static func loadURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        guard !providers.isEmpty else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        let collector = Collector(count: providers.count)
        let group = DispatchGroup()

        for (index, provider) in providers.enumerated() {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                defer { group.leave() }
                if let url = Self.url(from: item) {
                    collector.set(url, at: index)
                }
            }
        }

        group.notify(queue: .main) {
            completion(collector.urls)
        }
    }

    /// Providers hand back either the URL's `dataRepresentation` or, depending on
    /// the source app, the `URL` itself. Accept both.
    private static func url(from item: NSSecureCoding?) -> URL? {
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        if let url = item as? URL {
            return url
        }
        return nil
    }

    /// Thread-safe fixed-size collection of results, indexed by provider position.
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [URL?]

        init(count: Int) {
            storage = Array(repeating: nil, count: count)
        }

        func set(_ url: URL, at index: Int) {
            lock.lock()
            defer { lock.unlock() }
            guard storage.indices.contains(index) else { return }
            storage[index] = url
        }

        var urls: [URL] {
            lock.lock()
            defer { lock.unlock() }
            return storage.compactMap { $0 }
        }
    }
}
