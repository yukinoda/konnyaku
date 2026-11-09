import SwiftUI

/// Frees the model before any termination. ggml's Metal teardown asserts if
/// the process exits while a model is still loaded.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set before launch finishes so a Service request that cold-launches
    /// Konnyaku finds its provider.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSUpdateDynamicServices()
        GlobalHotKey.shared.start()
        Installer.offerCleanup()
    }

    /// The "Translate with Konnyaku" service (NSMessage = translateSelection).
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
struct KonnyakuApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    // Not observed here: the views observe it, so model changes don't
    // rebuild the whole scene.
    private let model = TranslationViewModel.shared

    var body: some Scene {
        MenuBarExtra("Konnyaku", systemImage: "character.bubble") {
            MenuBarMenu(model: model)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model)
        }
    }
}

struct MenuBarMenu: View {
    let model: TranslationViewModel
    @ObservedObject private var hotKeys = GlobalHotKey.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        // The global Carbon hotkey handles the shortcut; a menu key equivalent
        // could fire it a second time while the menu is open, so only show it.
        Button("Translate Clipboard (\(hotKeys.hotKey.displayString))") {
            TranslatePanelController.shared.toggleWithClipboard()
        }

        Button("Open Translator…") {
            TranslatePanelController.shared.showEditor()
        }

        Divider()

        Button("Settings…") {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")

        Button("About Konnyaku") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(nil)
        }

        Divider()

        Button("Quit Konnyaku") {
            model.quit()
        }
        .keyboardShortcut("q")
    }
}

extension NSWindow {
    /// True while this window's text field holds IME marked text. Keys and
    /// shortcuts then belong to the composition.
    var isComposingText: Bool {
        let inputClient = firstResponder as? NSTextInputClient
        return inputClient?.hasMarkedText() == true
    }
}
