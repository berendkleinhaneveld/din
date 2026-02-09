import AVFoundation

enum MetadataLoader {
    static func load(url: URL) async -> Track {
        let asset = AVAsset(url: url)
        var title: String?
        var artist = "Unknown Artist"
        var album = "Unknown Album"
        var duration: TimeInterval = 0

        do {
            let metadata = try await asset.load(.metadata, .duration)
            duration = metadata.1.seconds.isFinite ? metadata.1.seconds : 0

            for item in metadata.0 {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    title = try await item.load(.stringValue)
                case .commonKeyArtist:
                    if let value = try await item.load(.stringValue) {
                        artist = value
                    }
                case .commonKeyAlbumName:
                    if let value = try await item.load(.stringValue) {
                        album = value
                    }
                default:
                    break
                }
            }
        } catch {}

        return Track(url: url, title: title, artist: artist, album: album, duration: duration)
    }

    static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "alac", "caf"
    ]

    static func audioFiles(in urls: [URL]) -> [URL] {
        var results: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                    for case let fileURL as URL in enumerator {
                        if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                            results.append(fileURL)
                        }
                    }
                }
            } else if supportedExtensions.contains(url.pathExtension.lowercased()) {
                results.append(url)
            }
        }
        return results.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
