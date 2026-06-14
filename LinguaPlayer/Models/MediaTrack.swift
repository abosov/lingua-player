import Foundation

struct MediaTrack: Identifiable, Hashable {
    enum Kind {
        case audio
        case subtitle
    }

    let id: Int
    let kind: Kind
    let language: String?
    let codec: String?
    let description: String?
}
