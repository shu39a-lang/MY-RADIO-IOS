import SwiftUI

@main
struct MyRadioApp: App {
    @StateObject private var store = RadioStore()
    @StateObject private var player = SpeechPlayer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(player)
                .preferredColorScheme(.dark)
        }
    }
}
