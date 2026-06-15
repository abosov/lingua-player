import Foundation
import Combine

/// Persistent list of the last few opened videos. Backed by UserDefaults; the
/// single shared instance is observed by both the setup view and the player
/// view model so position updates show up immediately on the recents list
/// the next time the user returns to the setup screen.
@MainActor
final class RecentFilesStore: ObservableObject {
    static let shared = RecentFilesStore()

    @Published private(set) var entries: [RecentFile] = []

    private static let defaultsKey = "lingua.recentFiles"
    private static let maxEntries = 3

    private init() {
        load()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey) else { return }
        let decoded = (try? JSONDecoder().decode([RecentFile].self, from: data)) ?? []
        entries = Array(decoded.prefix(Self.maxEntries))
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    /// Move the entry to the front (most recent) and trim to maxEntries.
    func upsert(_ entry: RecentFile) {
        entries.removeAll { $0.fileURL == entry.fileURL }
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
        persist()
    }

    func remove(fileURL: URL) {
        let countBefore = entries.count
        entries.removeAll { $0.fileURL == fileURL }
        if entries.count != countBefore {
            persist()
        }
    }
}
