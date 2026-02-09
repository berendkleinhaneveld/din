import AVFoundation
import Combine
import SwiftUI

@MainActor
final class PlaybackTime: ObservableObject {
    static let shared = PlaybackTime()
    @Published var currentTime: TimeInterval = 0
}

@MainActor
final class PlaylistManager: ObservableObject {
    static let shared = PlaylistManager()

    @Published var tracks: [Track] = []
    @Published var currentIndex: Int?
    @Published var isPlaying = false
    @Published var volume: Float = 0.75
    @Published var repeatEnabled = false
    @Published var selection: Set<Track.ID> = []

    var currentTime: TimeInterval {
        get { PlaybackTime.shared.currentTime }
        set { PlaybackTime.shared.currentTime = newValue }
    }

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var tickCount = 0

    var currentTrack: Track? {
        guard let i = currentIndex, tracks.indices.contains(i) else { return nil }
        return tracks[i]
    }

    var totalDuration: TimeInterval {
        tracks.reduce(0) { $0 + $1.duration }
    }

    var hasContent: Bool { !tracks.isEmpty }

    init() {
        restoreState()
    }

    // MARK: - Playback Controls

    func play() {
        if currentIndex == nil && !tracks.isEmpty {
            playTrack(at: 0)
            return
        }
        if player == nil, let track = currentTrack {
            let resumeTime = currentTime
            loadAndPlay(track: track)
            if resumeTime > 0 {
                seek(to: resumeTime)
            }
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
        saveState()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func next() {
        guard !tracks.isEmpty else { return }
        if let current = currentIndex {
            let nextIndex = current + 1
            if nextIndex < tracks.count {
                playTrack(at: nextIndex)
            } else if repeatEnabled {
                playTrack(at: 0)
            } else {
                stop()
                currentIndex = 0
            }
        } else {
            playTrack(at: 0)
        }
    }

    func previous() {
        guard !tracks.isEmpty else { return }
        if currentTime > 3, let idx = currentIndex {
            playTrack(at: idx)
            return
        }
        if let current = currentIndex {
            let prevIndex = current - 1
            if prevIndex >= 0 {
                playTrack(at: prevIndex)
            } else if repeatEnabled {
                playTrack(at: tracks.count - 1)
            } else {
                playTrack(at: 0)
            }
        } else {
            playTrack(at: 0)
        }
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
        saveState()
    }

    func toggleRepeat() {
        repeatEnabled.toggle()
        saveState()
    }

    // MARK: - Playlist Management

    func addTracks(urls: [URL], at index: Int? = nil) {
        let audioURLs = MetadataLoader.audioFiles(in: urls)
        guard !audioURLs.isEmpty else { return }

        let insertionIndex = index ?? tracks.count
        let placeholders = audioURLs.map { Track(url: $0) }
        tracks.insert(contentsOf: placeholders, at: min(insertionIndex, tracks.count))

        if let ci = currentIndex, insertionIndex <= ci {
            currentIndex = ci + placeholders.count
        }

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
        saveState()
    }

    func removeTracks(ids: Set<Track.ID>) {
        let wasPlaying = isPlaying
        let currentID = currentTrack?.id

        tracks.removeAll { ids.contains($0.id) }
        selection.subtract(ids)

        if let cid = currentID {
            if ids.contains(cid) {
                stop()
                if !tracks.isEmpty {
                    currentIndex = min(currentIndex ?? 0, tracks.count - 1)
                    if wasPlaying { play() }
                } else {
                    currentIndex = nil
                }
            } else {
                currentIndex = tracks.firstIndex(where: { $0.id == cid })
            }
        }
        saveState()
    }

    func clearPlaylist() {
        stop()
        tracks.removeAll()
        currentIndex = nil
        selection.removeAll()
        saveState()
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
        saveState()
    }

    // MARK: - Persistence

    func saveState() {
        let defaults = UserDefaults.standard
        defaults.set(tracks.map { $0.url.absoluteString }, forKey: "box.playlist")
        defaults.set(currentIndex ?? -1, forKey: "box.currentIndex")
        defaults.set(currentTime, forKey: "box.currentTime")
        defaults.set(Double(volume), forKey: "box.volume")
        defaults.set(repeatEnabled, forKey: "box.repeat")
    }

    private func restoreState() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: "box.volume") != nil {
            volume = Float(defaults.double(forKey: "box.volume"))
        }
        repeatEnabled = defaults.bool(forKey: "box.repeat")

        guard let urlStrings = defaults.stringArray(forKey: "box.playlist") else { return }
        let urls = urlStrings.compactMap { URL(string: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }

        tracks = urls.map { Track(url: $0) }

        for (index, url) in urls.enumerated() {
            Task {
                let track = await MetadataLoader.load(url: url)
                if index < self.tracks.count, self.tracks[index].url == url {
                    self.tracks[index].title = track.title
                    self.tracks[index].artist = track.artist
                    self.tracks[index].album = track.album
                    self.tracks[index].duration = track.duration
                }
            }
        }

        let savedIndex = defaults.integer(forKey: "box.currentIndex")
        if savedIndex >= 0, tracks.indices.contains(savedIndex) {
            currentIndex = savedIndex
        }
        currentTime = defaults.double(forKey: "box.currentTime")
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
        tickCount = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let p = self.player {
                    self.currentTime = p.currentTime
                    if !p.isPlaying && self.isPlaying {
                        self.next()
                    }
                }
                self.tickCount += 1
                if self.tickCount % 50 == 0 {
                    self.saveState()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
