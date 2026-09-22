import SwiftUI
import RefAppWatchCore

@main
struct RefAppWatchApp: App {
    @State private var model = LiveMatchModel()

    var body: some Scene {
        WindowGroup { LiveMatchView(model: model) }
    }
}
