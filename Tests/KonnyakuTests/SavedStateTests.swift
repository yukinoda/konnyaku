import XCTest
@testable import Konnyaku

/// Pins what earlier versions left on users' Macs. Keys, field names and
/// file-name formats are literals on purpose: if a refactor renames one,
/// these fail instead of users silently losing their shortcut or
/// re-downloading a model. A deliberate model revision bump changes the
/// file name and must still pass.
final class SavedStateTests: XCTestCase {
    func testHotKeyStoredByEarlierVersionsStillLoads() throws {
        let suiteName = "SavedStateTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        // ⌃⌥T in the JSON format v0.1.0 saves.
        let json = #"{"keyCode":17,"carbonModifiers":6144}"#
        defaults.set(Data(json.utf8), forKey: "translateHotKey")

        let expected = HotKey(keyCode: 17, carbonModifiers: 6144)
        XCTAssertEqual(HotKey.loadStored(from: defaults), expected)
    }

    /// TranslationViewModel always uses the standard defaults, so this
    /// restores the previous value afterwards.
    @MainActor
    func testModelChoiceKeepsItsKey() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "modelSize")
        defer {
            defaults.set(previous, forKey: "modelSize")
        }

        defaults.set("2b", forKey: "modelSize")
        let model = TranslationViewModel()
        XCTAssertEqual(model.modelSize, .large)

        model.modelSize = .small
        XCTAssertEqual(defaults.string(forKey: "modelSize"), "0.8b")
    }

    func testDownloadedModelFilesKeepTheirNames() {
        let small = ModelSize.small
        let smallPrefix = small.sha256.prefix(12)
        XCTAssertEqual(
            small.localFileName,
            "\(smallPrefix)-plamo-3-translate-0.8b-Q4_K_M.gguf"
        )

        let large = ModelSize.large
        let largePrefix = large.sha256.prefix(12)
        XCTAssertEqual(
            large.localFileName,
            "\(largePrefix)-plamo-3-translate-2b-Q4_K_M.gguf"
        )
    }

    func testModelsStayInTheSameFolder() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let expected = home.appendingPathComponent(
            "Library/Application Support/Konnyaku",
            isDirectory: true
        )
        XCTAssertEqual(ModelStore.directory.standardizedFileURL, expected.standardizedFileURL)
    }
}
