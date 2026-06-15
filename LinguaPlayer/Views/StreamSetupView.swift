import SwiftUI

struct StreamSetupView: View {
    @ObservedObject var viewModel: StreamSetupViewModel
    @ObservedObject private var recents = RecentFilesStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack {
                Button("Open Video…") {
                    viewModel.openFile()
                }
                .controlSize(.large)
                .keyboardShortcut("o", modifiers: .command)
                .disabled(viewModel.isLoading)

                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                    Text("Probing tracks…")
                        .foregroundStyle(.secondary)
                }
            }

            if !recents.entries.isEmpty {
                recentsSection
            }

            if let url = viewModel.fileURL {
                Text(url.path)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let message = viewModel.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            if !viewModel.audioTracks.isEmpty || !viewModel.subtitleTracks.isEmpty {
                tracksList
                continueBar
            } else {
                Spacer()
                placeholder
                Spacer()
            }
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 480)
        .overlay { preparingOverlay }
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent")
                .font(.headline)
            ForEach(recents.entries) { entry in
                RecentFileRow(entry: entry) {
                    viewModel.openRecent(entry)
                }
            }
        }
    }

    @ViewBuilder
    private var preparingOverlay: some View {
        if viewModel.isPreparing {
            ZStack {
                Color.black.opacity(0.55)
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                    Text(viewModel.preparingStatus ?? "Preparing…")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .padding(28)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Lingua Player")
                .font(.largeTitle.bold())
            Text("Click an audio track to assign A/B, and a subtitle track for phrases.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var placeholder: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "film")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("No file loaded")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var tracksList: some View {
        List {
            Section("Audio Tracks (\(viewModel.audioTracks.count))") {
                if viewModel.audioTracks.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.audioTracks) { track in
                        AudioTrackRow(
                            track: track,
                            channel: viewModel.channel(for: track.id),
                            onTap: { viewModel.toggleAssignment(for: track.id) }
                        )
                    }
                }
            }

            Section("Subtitle Tracks (\(viewModel.subtitleTracks.count))") {
                if viewModel.subtitleTracks.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.subtitleTracks) { track in
                        SubtitleTrackRow(
                            track: track,
                            isActive: viewModel.isActiveSubtitle(track.id),
                            onTap: { viewModel.toggleSubtitle(for: track.id) }
                        )
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var continueBar: some View {
        HStack {
            Text(continueHint)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Continue") {
                viewModel.continueToPlayer()
            }
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!viewModel.canContinue || viewModel.isPreparing)
        }
    }

    private var continueHint: String {
        if viewModel.channelA == nil      { return "Pick Channel A (primary audio)." }
        if viewModel.channelB == nil      { return "Pick Channel B (secondary audio)." }
        if viewModel.activeSubtitle == nil { return "Pick the subtitle track." }
        return "All assignments set."
    }
}

private struct AudioTrackRow: View {
    let track: MediaTrack
    let channel: Channel?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            TrackRow(track: track, badge: channel.map { Badge(for: $0) })
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SubtitleTrackRow: View {
    let track: MediaTrack
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            TrackRow(track: track, badge: isActive ? Badge.subtitle : nil)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct TrackRow: View {
    let track: MediaTrack
    let badge: Badge?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if track.isExternal {
                    Text("EXT")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.purple)
                } else {
                    Text("#\(track.id)")
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 48, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.language ?? "Unknown language")
                    .font(.body)

                HStack(spacing: 8) {
                    if let codec = track.codec {
                        Label(codec, systemImage: "waveform")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let description = track.description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if let badge {
                BadgeView(badge: badge)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct Badge {
    let label: String
    let color: Color

    static let subtitle = Badge(label: "S", color: .green)

    init(label: String, color: Color) {
        self.label = label
        self.color = color
    }

    init(for channel: Channel) {
        self.label = channel.label
        switch channel {
        case .a: self.color = .blue
        case .b: self.color = .orange
        }
    }
}

private struct BadgeView: View {
    let badge: Badge

    var body: some View {
        Text(badge.label)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(badge.color, in: Circle())
    }
}

private struct RecentFileRow: View {
    let entry: RecentFile
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: entry.fileExists ? "play.circle.fill" : "questionmark.circle")
                    .font(.title2)
                    .foregroundStyle(entry.fileExists ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.fileName)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 12) {
                        Text(formatProgress(entry))
                            .monospaced()
                        Text(formatLabels(entry))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if !entry.fileExists {
                        Text("File not found")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .opacity(entry.fileExists ? 1.0 : 0.55)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formatProgress(_ entry: RecentFile) -> String {
        let pos = Self.formatTime(entry.lastPositionSeconds)
        let total = Self.formatTime(entry.totalDurationSeconds)
        return "\(pos) / \(total)"
    }

    private func formatLabels(_ entry: RecentFile) -> String {
        "A: \(entry.audioALabel), B: \(entry.audioBLabel), S: \(entry.subtitleLabel)"
    }

    private static func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t > 0 else { return "—" }
        let total = Int(t)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
