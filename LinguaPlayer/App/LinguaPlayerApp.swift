import SwiftUI

@main
struct LinguaPlayerApp: App {
    var body: some Scene {
        WindowGroup("Lingua Player") {
            RootView()
        }
        .windowResizability(.contentMinSize)
    }
}

private struct RootView: View {
    @StateObject private var setupViewModel = StreamSetupViewModel()

    var body: some View {
        if setupViewModel.hasContinuedToPlayer,
           let a = setupViewModel.channelA,
           let b = setupViewModel.channelB,
           let s = setupViewModel.activeSubtitle {
            MainPlayerView(channelA: a, channelB: b, subtitle: s)
        } else {
            StreamSetupView(viewModel: setupViewModel)
        }
    }
}
