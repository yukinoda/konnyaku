import XCTest
@testable import Konnyaku

/// Pins what earlier versions left on users' Macs. The expected values are
/// literals on purpose: if a refactor renames a key, a field or a file, these
/// fail instead of users silently losing their shortcut or re-downloading
/// a model.
final class SavedStateTests: XCTestCase {
    func testHotKeyStoredByEarlierVersionsStillLoads() throws {
        let suiteName = "SavedStateTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        // ⌃⌥T exactly as v0.1.0 writes it.
        let json = #"{"keyCode":17,"carbonModifiers":6144}"#
        defaults.set(Data(json.utf8), forKey: "translateHotKey")

        let expected = HotKey(keyCode: 17, carbonModifiers: 6144)
        XCTAssertEqual(HotKey.loadStored(from: defaults), expected)
        XCTAssertEqual(expected, HotKey.default)
    }

    @MainActor
    func testModelChoiceStoredByEarlierVersionsStillLoads() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "modelSize")
        defer {
            defaults.set(previous, forKey: "modelSize")
        }

        defaults.set("2b", forKey: "modelSize")
        XCTAssertEqual(TranslationViewModel().modelSize, .large)
        defaults.set("0.8b", forKey: "modelSize")
        XCTAssertEqual(TranslationViewModel().modelSize, .small)
    }

    func testDownloadedModelFilesKeepTheirNames() {
        XCTAssertEqual(
            ModelSize.small.localFileName,
            "3dbb09295bfd-plamo-3-translate-0.8b-Q4_K_M.gguf"
        )
        XCTAssertEqual(
            ModelSize.large.localFileName,
            "2c288ecc7ebf-plamo-3-translate-2b-Q4_K_M.gguf"
        )
    }

    func testModelsStayInTheSameFolder() {
        let path = ModelStore.directory.path
        XCTAssertTrue(path.hasSuffix("/Library/Application Support/Konnyaku"), path)
    }

    func testDownloadURLsArePinned() {
        XCTAssertEqual(
            ModelSize.small.downloadURL.absoluteString,
            "https://huggingface.co/pfnet/plamo-3-translate-0.8b-GGUF/resolve/"
                + "03891e907db8a43c97d3a7c75add125cc6d1f96a/"
                + "plamo-3-translate-0.8b-Q4_K_M.gguf"
        )
        XCTAssertEqual(
            ModelSize.large.downloadURL.absoluteString,
            "https://huggingface.co/pfnet/plamo-3-translate-2b-GGUF/resolve/"
                + "f2b4599dff9b3e45c62567eac15e83186b4cb64e/"
                + "plamo-3-translate-2b-Q4_K_M.gguf"
        )
    }
}
