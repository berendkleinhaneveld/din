import AVFoundation
import Combine
import SwiftUI

@MainActor
final class PlaylistManager: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var currentIndex: Int?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var volume: Float = 0.75

    private var player: AVAudioPlayer?
    private var timer: Timer?

    var currentTrack: Track? {
        guard let i = currentIndex, tracks.indices.contains(i) else { return nil }
        return tracks[i]
    }

    // MARK: - Playback Controls

    func play() {
        if player == nil, let track = currentTrack {
            loadAndPlay(track: track)
            return
        }
        player?.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func next() {
        guard !tracks.isEmpty else { return }
        let nextIndex: Int
        if let current = currentIndex {
            nextIndex = (current + 1) % tracks.count
        } else {
            nextIndex = 0
        }
        playTrack(at: nextIndex)
    }

    func previous() {
        guard !tracks.isEmpty else { return }
        // If more than 3 seconds in, restart current track
        if currentTime > 3, let idx = currentIndex {
            playTrack(at: idx)
            return
        }
        let prevIndex: Int
        if let current = currentIndex {
            prevIndex = (current - 1 + tracks.count) % tracks.count
        } else {
            prevIndex = 0
        }
        playTrack(at: prevIndex)
    }

    func playTrack(at index: Int) {
        guard tracks.indices.contains(index) else { return }
        currentIndex = index
        loadAndPlay(track: tracks[index])
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    func setVolume(_ vol: Float) {
        volume = vol
        player?.volume = vol
    }

    // MARK: - Playlist Management

    func addTracks(urls: [URL], at index: Int? = nil) {
        let audioURLs = MetadataLoader.audioFiles(in: urls)
        guard !audioURLs.isEmpty else { return }

        let insertionIndex = index ?? tracks.count
        let placeholders = audioURLs.map { Track(url: $0) }
        tracks.insert(contentsOf: placeholders, at: min(insertionIndex, tracks.count))

        // Adjust currentIndex if insertion is before it
        if let ci = currentIndex, insertionIndex <= ci {
            currentIndex = ci + placeholders.count
        }

        // Load metadata asynchronously
        let startIndex = insertionIndex
        for (offset, url) in audioURLs.enumerated() {
            Task {
                let track = await MetadataLoader.load(url: url)
                let targetIndex = startIndex + offset
                if targetIndex < tracks.count, tracks[targetIndex].url == url {
                    tracks[targetIndex].title = track.title
                    tracks[targetIndex].artist = track.artist
                    tracks[targetIndex].album = track.album
                    tracks[targetIndex].duration = track.duration
                }
            }
        }
    }

    func removeTracks(ids: Set<Track.ID>) {
        let wasPlaying = isPlaying
        let currentID = currentTrack?.id

        tracks.removeAll { ids.contains($0.id) }

        if let cid = currentID {
            if ids.contains(cid) {
                // Current track removed
                stop()
                if !tracks.isEmpty {
                    currentIndex = min(currentIndex ?? 0, tracks.count - 1)
                    if wasPlaying { play() }
                } else {
                    currentIndex = nil
                }
            } else {
                // Update index to match current track's new position
                currentIndex = tracks.firstIndex(where: { $0.id == cid })
            }
        }
    }

    func clearPlaylist() {
        stop()
        tracks.removeAll()
        currentIndex = nil
    }

    func replacePlaylist(urls: [URL]) {
        clearPlaylist()
        addTracks(urls: urls)
        if !tracks.isEmpty {
            playTrack(at: 0)
        }
    }

    func moveTrack(from source: IndexSet, to destination: Int) {
        let currentID = currentTrack?.id
        tracks.move(fromOffsets: source, toOffset: destination)
        if let cid = currentID {
            currentIndex = tracks.firstIndex(where: { $0.id == cid })
        }
    }

    // MARK: - Private

    private func loadAndPlay(track: Track) {
        stop()
        do {
            player = try AVAudioPlayer(contentsOf: track.url)
            player?.volume = volume
            player?.prepareToPlay()
            player?.play()
            isPlaying = true
            startTimer()
        } catch {
            isPlaying = false
        }
    }

    private func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        stopTimer()
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let p = self.player {
                    self.currentTime = p.currentTime
                    if !p.isPlaying && self.isPlaying {
                        // Track finished
                        self.next()
                    }
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
