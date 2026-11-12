import XCTest
@testable import Konnyaku

final class TranslatorTests: XCTestCase {
    /// A file the GGUF loader rejects is deleted, so the next attempt
    /// downloads it again and the error's "was deleted" is true. Its path
    /// has no pinned hash, so it can't be verified.
    func testRejectedModelFileIsDeleted() async throws {
        let url = try makeJunkModelFile()
        let translator = makeTranslator(expectedSHA256: ModelStore.expectedSHA256(forPath:))

        do {
            _ = try await translator.translate([], modelPath: url.path)
            XCTFail("expected modelFileInvalid")
        } catch TranslatorError.modelFileInvalid {
            // Expected.
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    /// A rejected file whose hash differs from its pin is corrupt and deleted.
    func testRejectedModelFileWithWrongHashIsDeleted() async throws {
        let url = try makeJunkModelFile()
        let wrongHash = String(repeating: "0", count: 64)
        let translator = makeTranslator(expectedSHA256: { _ in wrongHash })

        do {
            _ = try await translator.translate([], modelPath: url.path)
            XCTFail("expected modelFileInvalid")
        } catch TranslatorError.modelFileInvalid {
            // Expected.
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    /// A rejected file that still matches its pinned hash is not corrupt
    /// (e.g. the load ran out of memory), so it is kept: deleting it would
    /// make every retry download the same file again.
    func testRejectedModelFileWithMatchingHashIsKept() async throws {
        let url = try makeJunkModelFile()
        let matchingHash = try ModelStore.sha256Hex(of: url)
        let translator = makeTranslator(expectedSHA256: { _ in matchingHash })

        do {
            _ = try await translator.translate([], modelPath: url.path)
            XCTFail("expected loadFailed")
        } catch TranslatorError.loadFailed {
            // Expected.
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    /// The production lookup finds each model's pin from the path the app
    /// loads it from, and nothing for any other path.
    func testExpectedSHA256ComesFromTheModelsPath() {
        for model in ModelSize.allCases {
            let path = ModelStore.localURL(for: model).path
            XCTAssertEqual(ModelStore.expectedSHA256(forPath: path), model.sha256)
        }
        let otherPath = FileManager.default.temporaryDirectory.appendingPathComponent("x.gguf").path
        XCTAssertNil(ModelStore.expectedSHA256(forPath: otherPath))
    }

    private func makeJunkModelFile() throws -> URL {
        let name = "not-a-model-\(UUID().uuidString).gguf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try Data("not a GGUF file".utf8).write(to: url)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func makeTranslator(expectedSHA256: @escaping (String) -> String?) -> Translator {
        let translator = Translator(expectedSHA256: expectedSHA256)
        // Cancels the idle-unload task that translate schedules.
        addTeardownBlock {
            await translator.shutDown()
        }
        return translator
    }
}
