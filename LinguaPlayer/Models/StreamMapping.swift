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
    /// Temporary MP4 produced by MediaPreparer.remux. Contains the original
    /// video stream plus two audio tracks: index 0 is Channel A's source,
    /// index 1 is Channel B's source. AVPlayer reads this file directly.
    let remuxedURL: URL
    let cues: [SubtitleCue]
}
