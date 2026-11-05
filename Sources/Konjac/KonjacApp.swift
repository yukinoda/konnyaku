import SwiftUI

/// Frees the model before any termination. ggml's Metal teardown asserts if
/// the process exits while a model is still loaded.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set before launch finishes so a Service request that cold-launches
    /// konjac finds its provider.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSUpdateDynamicServices()
        GlobalHotKey.register()
    }

    /// The "Translate with konjac" service (NSMessage = translateSelection).
    @objc func translateSelection(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let text = pasteboard.string(forType: .string) ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            error.pointee = "No text was selected." as NSString
            return
        }
        Task { @MainActor in
            TranslatePanelController.shared.show(text: text)
        }
    }

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
    // Not observed here: ContentView observes it, so model changes don't
    // rebuild the whole scene.
    private let model = TranslationViewModel.shared

    var body: some Scene {
        MenuBarExtra("konjac", systemImage: "character.bubble") {
            ContentView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
