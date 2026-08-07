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

    init(
        source: String,
        title: String,
        artist: String,
        album: String,
        isPlaying: Bool,
        duration: Double,
        position: Double,
        artworkURL: String = ""
    ) {
        self.source = source
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.duration = duration
        self.position = position
        self.artworkURL = artworkURL
    }
}

enum MediaCommand: String, Codable, CaseIterable, Sendable {
    case togglePlayPause
    case next
    case previous
}
