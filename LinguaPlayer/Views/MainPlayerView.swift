import SwiftUI

struct MainPlayerView: View {
    let channelA: Int
    let channelB: Int

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text("Player coming soon")
                .font(.title.bold())
            Text("Channel A: track #\(channelA)   ·   Channel B: track #\(channelB)")
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(minWidth: 640, minHeight: 480)
    }
}
