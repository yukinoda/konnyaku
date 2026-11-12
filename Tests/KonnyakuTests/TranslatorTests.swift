import XCTest
@testable import Konnyaku

final class TranslatorTests: XCTestCase {
    /// A file the GGUF loader rejects is deleted, so the next attempt
    /// downloads it again and the error's "was deleted" is true.
    func testRejectedModelFileIsDeleted() async throws {
        let name = "not-a-model-\(UUID().uuidString).gguf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try Data("not a GGUF file".utf8).write(to: url)
        defer {
            try? FileManager.default.removeItem(at: url)
        }
        let translator = Translator()
        // Cancels the idle-unload task that translate schedules.
        addTeardownBlock {
            await translator.shutDown()
        }

        do {
            _ = try await translator.translate([], modelPath: url.path)
            XCTFail("expected modelFileInvalid")
        } catch TranslatorError.modelFileInvalid {
            // Expected.
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
