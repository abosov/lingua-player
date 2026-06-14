import SwiftUI

struct MainPlayerView: View {
    @StateObject private var viewModel: PlayerViewModel

    init(setup: PlaybackSetup) {
        _viewModel = StateObject(wrappedValue: PlayerViewModel(setup: setup))
    }

    var body: some View {
        VStack(spacing: 0) {
            videoArea
            SubtitleOverlayView(text: viewModel.currentCueText ?? "")
            ControlBarView(viewModel: viewModel)
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color.black)
        .background(keyboardLayer)
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    private var videoArea: some View {
        ZStack(alignment: .topTrailing) {
            VLCVideoRepresentable(drawable: viewModel.drawableView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            channelIndicator
                .padding(16)
            subtitleStatusBadge
        }
        .background(Color.black)
    }

    private var channelIndicator: some View {
        Text(viewModel.activeChannel.label)
            .font(.title2.bold())
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(channelColor, in: Circle())
            .shadow(radius: 4)
    }

    private var channelColor: Color {
        switch viewModel.activeChannel {
        case .a: return .blue
        case .b: return .orange
        }
    }

    @ViewBuilder
    private var subtitleStatusBadge: some View {
        if let status = viewModel.subtitleStatus {
            VStack {
                Spacer()
                Label(status, systemImage: "captions.bubble")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.6), in: Capsule())
                    .padding(.bottom, 16)
            }
        }
    }

    private var keyboardLayer: some View {
        Group {
            Button("") { viewModel.previousPhrase() }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { viewModel.nextPhrase() }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { viewModel.toggleChannel() }
                .keyboardShortcut("a", modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }
}

private struct VLCVideoRepresentable: NSViewRepresentable {
    let drawable: NSView

    func makeNSView(context: Context) -> NSView { drawable }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
