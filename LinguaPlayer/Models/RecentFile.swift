import Foundation

/// Where to find the subtitle cues for a recent-file session.
enum SubtitleSource: Codable, Equatable, Hashable {
    case embedded(index: Int)
    case external(path: String)
}

/// A persisted "open this file with these settings" record. Stored in
/// UserDefaults via RecentFilesStore; everything inside must be Codable.
struct RecentFile: Codable, Identifiable, Equatable, Hashable {
    let fileURL: URL
    /// 0-based position in the source's audio-only track list — matches
    /// ffmpeg's `0:a:N` selector and StreamSetupViewModel's stored indices.
    let audioTrackAIndex: Int
    let audioTrackBIndex: Int
    let subtitleSource: SubtitleSource

    let audioALabel: String
    let audioBLabel: String
    let subtitleLabel: String

    var lastPositionSeconds: TimeInterval
    var totalDurationSeconds: TimeInterval
    var lastOpened: Date

    var id: String { fileURL.path }
    var fileName: String { fileURL.lastPathComponent }
    var fileExists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }
}
