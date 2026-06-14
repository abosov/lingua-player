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
