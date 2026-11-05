import SwiftUI

/// Frees the model before any termination. ggml's Metal teardown asserts if
/// the process exits while a model is still loaded.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await Translator.shared.shutDown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct KonjacApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var model = TranslationViewModel()

    var body: some Scene {
        MenuBarExtra("konjac", systemImage: "character.bubble") {
            ContentView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
