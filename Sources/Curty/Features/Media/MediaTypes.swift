import Foundation

struct MediaSnapshot: Codable, Equatable, Sendable {
    var source: String
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var duration: Double
    var position: Double
    /// Empty unless the player publishes a cover link; the image itself is never
    /// carried here.
    var artworkURL: String
    /// Громкость самого плеера, 0…100. nil — плеер её не сообщил, и тогда
    /// ползунок не показывается: лучше без него, чем врущий.
    var volume: Double?

    init(
        source: String,
        title: String,
        artist: String,
        album: String,
        isPlaying: Bool,
        duration: Double,
        position: Double,
        artworkURL: String = "",
        volume: Double? = nil
    ) {
        self.source = source
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.duration = duration
        self.position = position
        self.artworkURL = artworkURL
        self.volume = volume
    }
}

enum MediaCommand: String, Codable, CaseIterable, Sendable {
    case togglePlayPause
    case next
    case previous
}
