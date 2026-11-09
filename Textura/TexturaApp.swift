import SwiftUI

@main
struct TexturaApp: App {
    @StateObject private var recents = Recents()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(recents)
        }
    }
}
