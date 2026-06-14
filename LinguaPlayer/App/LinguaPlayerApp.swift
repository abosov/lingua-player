import SwiftUI

@main
struct LinguaPlayerApp: App {
    var body: some Scene {
        WindowGroup("Lingua Player") {
            StreamSetupView()
        }
        .windowResizability(.contentMinSize)
    }
}
