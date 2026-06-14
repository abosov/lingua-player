import Foundation

enum Channel: CaseIterable {
    case a
    case b

    var label: String {
        switch self {
        case .a: return "A"
        case .b: return "B"
        }
    }
}

struct PlaybackSetup: Equatable {
    let fileURL: URL
    /// 0-based position of Channel A's track among the file's audio tracks.
    let audioTrackAIndex: Int
    /// 0-based position of Channel B's track among the file's audio tracks.
    let audioTrackBIndex: Int
    /// 0-based position of the picked subtitle track among the file's
    /// subtitle tracks. Used both for VLCMediaPlayer.textTracks indexing
    /// and as ffmpeg's "-map 0:s:N" selector.
    let subtitleTrackIndex: Int
}
