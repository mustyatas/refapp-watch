import SwiftUI
import RefAppWatchCore

@main
struct RefAppWatchApp: App {
    @State private var model = LiveMatchModel()

    var body: some Scene {
        WindowGroup { StartView(model: model) }
    }
}

/// A match being played opens straight to it; otherwise the referee picks match or training.
struct StartView: View {
    let model: LiveMatchModel
    @State private var choice: String?

    var body: some View {
        if choice == "match" || (choice == nil && model.hasKickedOff && !model.clock(at: Date()).isFinished) {
            LiveMatchView(model: model)
        } else {
            NavigationStack {
                List {
                    Button("Maç yönet") { choice = "match" }
                        .listItemTint(.green)
                    NavigationLink("Antrenman") { TrainingView(model: model) }
                }
                .navigationTitle("RefApp")
            }
        }
    }
}
