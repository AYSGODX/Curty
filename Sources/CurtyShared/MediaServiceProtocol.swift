import Foundation

public struct MediaSnapshot: Codable, Equatable, Sendable {
    public var source: String
    public var title: String
    public var artist: String
    public var album: String
    public var isPlaying: Bool
    public var duration: Double
    public var position: Double

    public init(
        source: String,
        title: String,
        artist: String,
        album: String,
        isPlaying: Bool,
        duration: Double,
        position: Double
    ) {
        self.source = source
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.duration = duration
        self.position = position
    }
}

public enum MediaCommand: String, Codable, CaseIterable, Sendable {
    case togglePlayPause
    case next
    case previous
}

public enum MediaWireFormat {
    public static func encode(_ snapshot: MediaSnapshot) throws -> Data {
        try JSONEncoder().encode(snapshot)
    }

    public static func decode(_ data: Data) throws -> MediaSnapshot {
        try JSONDecoder().decode(MediaSnapshot.self, from: data)
    }
}
