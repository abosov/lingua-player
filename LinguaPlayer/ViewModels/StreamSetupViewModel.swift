import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor
final class StreamSetupViewModel: ObservableObject {
    @Published private(set) var fileURL: URL?
    @Published private(set) var audioTracks: [MediaTrack] = []
    @Published private(set) var subtitleTracks: [MediaTrack] = []
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String?

    @Published private(set) var channelA: Int?
    @Published private(set) var channelB: Int?
    @Published private(set) var activeSubtitle: Int?
    @Published private(set) var hasContinuedToPlayer: Bool = false

    private let engine: VideoPlayerEngine

    init(engine: VideoPlayerEngine = VideoPlayerEngine()) {
        self.engine = engine
    }

    var canContinue: Bool {
        channelA != nil && channelB != nil && activeSubtitle != nil
    }

    func channel(for trackId: Int) -> Channel? {
        if channelA == trackId { return .a }
        if channelB == trackId { return .b }
        return nil
    }

    func isActiveSubtitle(_ trackId: Int) -> Bool {
        activeSubtitle == trackId
    }

    func toggleAssignment(for trackId: Int) {
        if channelA == trackId {
            channelA = nil
        } else if channelB == trackId {
            channelB = nil
        } else if channelA == nil {
            channelA = trackId
        } else if channelB == nil {
            channelB = trackId
        }
    }

    func toggleSubtitle(for trackId: Int) {
        if activeSubtitle == trackId {
            activeSubtitle = nil
        } else {
            activeSubtitle = trackId
        }
    }

    func continueToPlayer() {
        guard let a = channelA, let b = channelB, let s = activeSubtitle else { return }
        print("[StreamSetupViewModel] continue — channelA: \(a), channelB: \(b), subtitle: \(s)")
        hasContinuedToPlayer = true
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.message = "Select a video file"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = Self.allowedTypes

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await probe(url: url) }
    }

    private static var allowedTypes: [UTType] {
        var types: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        for ext in ["mkv", "avi", "mp4", "mov", "m4v"] {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }

    private func probe(url: URL) async {
        fileURL = url
        audioTracks = []
        subtitleTracks = []
        channelA = nil
        channelB = nil
        activeSubtitle = nil
        hasContinuedToPlayer = false
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let tracks = try await engine.probeTracks(at: url)
            audioTracks = tracks.filter { $0.kind == .audio }
            subtitleTracks = tracks.filter { $0.kind == .subtitle }
            if tracks.isEmpty {
                errorMessage = VideoProbeError.noTracksFound.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
