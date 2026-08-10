import SwiftUI

@main
struct AMYboardStarterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1020, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
