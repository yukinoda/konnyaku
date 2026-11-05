import SwiftUI

@main
struct KonjacApp: App {
    @StateObject private var model = TranslationViewModel()

    var body: some Scene {
        MenuBarExtra("konjac", systemImage: "character.bubble") {
            ContentView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
