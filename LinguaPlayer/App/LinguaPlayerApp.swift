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
        if let setup = setupViewModel.playbackSetup {
            MainPlayerView(setup: setup)
        } else {
            StreamSetupView(viewModel: setupViewModel)
        }
    }
}
