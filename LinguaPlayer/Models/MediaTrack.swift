import Foundation

struct MediaTrack: Identifiable, Hashable {
    enum Kind {
        case audio
        case subtitle
    }

    enum Source: Hashable {
        case embedded
        case external(URL)
    }

    let id: Int
    let kind: Kind
    let source: Source
    let language: String?
    let codec: String?
    let description: String?

    var externalURL: URL? {
        if case .external(let url) = source { return url }
        return nil
    }

    var isExternal: Bool { externalURL != nil }
}
