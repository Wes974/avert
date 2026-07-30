import SwiftUI

@main
struct AvertApp: App {
    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            ContentView()
        }
        // A Mac window gets a size the app chooses, not one inherited from a
        // phone. 940×720 shows a card and its explanation without scrolling,
        // which is the shape of every screen here.
        .defaultSize(width: 940, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            // Menu items that lead nowhere are worse than absent ones: this app
            // opens no documents and ships no help book.
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) {}
        }

        // Settings belongs in the app menu on a Mac, reachable with ⌘, from
        // anywhere — not as a third tab. It is the single most visible tell of
        // an app that was ported rather than written for the platform.
        Settings {
            SettingsView()
                .frame(width: 560, height: 620)
        }
        #else
        WindowGroup {
            ContentView()
        }
        #endif
    }
}
