import Foundation

enum M3U8 {
    static func write(tracks: [Track]) -> String {
        var lines = ["#EXTM3U"]
        for track in tracks {
            let duration = Int(track.duration)
            lines.append("#EXTINF:\(duration),\(track.title)")
            lines.append(track.url.path)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func parse(contents: String, relativeTo baseURL: URL) -> [URL] {
        let lines = contents.components(separatedBy: .newlines)
        var urls: [URL] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let url: URL
            if trimmed.hasPrefix("/") {
                url = URL(fileURLWithPath: trimmed)
            } else {
                url = baseURL.appendingPathComponent(trimmed)
            }
            if FileManager.default.fileExists(atPath: url.path) {
                urls.append(url)
            }
        }
        return urls
    }
}
