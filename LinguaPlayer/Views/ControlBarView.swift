import SwiftUI

struct ControlBarView: View {
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        HStack(spacing: 12) {
            Text(formatTime(viewModel.currentTime))
                .monospaced()
                .frame(width: 80, alignment: .leading)
                .foregroundStyle(.primary)

            Slider(
                value: Binding(
                    get: { min(viewModel.currentTime, max(viewModel.duration, 0)) },
                    set: { viewModel.seek(to: $0) }
                ),
                in: 0...max(viewModel.duration, 1)
            )

            Text(formatTime(viewModel.duration))
                .monospaced()
                .frame(width: 80, alignment: .trailing)
                .foregroundStyle(.primary)

            Button {
                viewModel.togglePlayback()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.space, modifiers: [])
        }
        .padding(16)
        .background(.thinMaterial)
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t > 0 else { return "0:00" }
        let total = Int(t)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
