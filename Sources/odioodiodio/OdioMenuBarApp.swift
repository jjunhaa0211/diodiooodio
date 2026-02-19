import SwiftUI

@main
struct OdioMenuBarApp: App {
    @StateObject private var viewModel = AudioControlViewModel()

    var body: some Scene {
        MenuBarExtra("Odio", systemImage: "speaker.wave.2.fill") {
            MenuBarContentView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appSettings) { }
        }
    }
}
