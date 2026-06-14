import Foundation

struct SubtitleCue: Identifiable, Equatable, Hashable {
    let id: Int
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}
