import SwiftUI

struct StreamSetupView: View {
    @ObservedObject var viewModel: StreamSetupViewModel

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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Lingua Player")
                .font(.largeTitle.bold())
            Text("Click an audio track to assign it to Channel A or Channel B.")
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
                        TrackRow(track: track, badge: nil)
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
            .disabled(!viewModel.bothChannelsAssigned)
        }
    }

    private var continueHint: String {
        switch (viewModel.channelA, viewModel.channelB) {
        case (nil, _): return "Pick Channel A (primary audio)."
        case (_, nil): return "Pick Channel B (secondary audio)."
        default:       return "Both channels assigned."
        }
    }
}

private struct AudioTrackRow: View {
    let track: MediaTrack
    let channel: Channel?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            TrackRow(track: track, badge: channel)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct TrackRow: View {
    let track: MediaTrack
    let badge: Channel?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("#\(track.id)")
                .monospaced()
                .frame(width: 48, alignment: .leading)
                .foregroundStyle(.secondary)

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
                ChannelBadge(channel: badge)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ChannelBadge: View {
    let channel: Channel

    var body: some View {
        Text(channel.label)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(color, in: Circle())
    }

    private var color: Color {
        switch channel {
        case .a: return .blue
        case .b: return .orange
        }
    }
}
