import Foundation

struct Track: Identifiable, Equatable, Hashable {
    let id: UUID
    let url: URL
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval

    init(id: UUID = UUID(), url: URL, title: String? = nil, artist: String = "Unknown Artist", album: String = "Unknown Album", duration: TimeInterval = 0) {
        self.id = id
        self.url = url
        self.title = title ?? url.deletingPathExtension().lastPathComponent
        self.artist = artist
        self.album = album
        self.duration = duration
    }

    var subtitle: String? {
        let hasArtist = artist != "Unknown Artist"
        let hasAlbum = album != "Unknown Album"
        if hasArtist && hasAlbum { return "\(artist) — \(album)" }
        if hasArtist { return artist }
        if hasAlbum { return album }
        return nil
    }
}
