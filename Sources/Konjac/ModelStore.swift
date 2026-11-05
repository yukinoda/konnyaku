import CryptoKit
import Foundation

/// A PLaMo 3 Translate GGUF pinned to a Hugging Face commit and SHA-256.
enum ModelSize: String, CaseIterable, Identifiable {
    case small = "0.8b"
    case large = "2b"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return "Fast (0.8B, 573 MB)"
        case .large: return "Higher quality (2B, 1.8 GB)"
        }
    }

    var fileName: String {
        "plamo-3-translate-\(rawValue)-Q4_K_M.gguf"
    }

    var revision: String {
        switch self {
        case .small: return "03891e907db8a43c97d3a7c75add125cc6d1f96a"
        case .large: return "f2b4599dff9b3e45c62567eac15e83186b4cb64e"
        }
    }

    var sha256: String {
        switch self {
        case .small: return "3dbb09295bfd3350231ba0dba92bc72cb14111ef1b034e37dad39d581bd86b9c"
        case .large: return "2c288ecc7ebfe60c3561726580da3583767f3c41ca3ef5c6825bf6c4cc060787"
        }
    }

    var downloadURL: URL {
        let repo = "pfnet/plamo-3-translate-\(rawValue)-GGUF"
        return URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(fileName)")!
    }
}

enum ModelStoreError: LocalizedError {
    case hashMismatch

    var errorDescription: String? {
        "Downloaded model failed its SHA-256 check and was deleted."
    }
}

enum ModelStore {
    static var directory: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return support.appendingPathComponent("konjac", isDirectory: true)
    }

    static func localURL(for model: ModelSize) -> URL {
        directory.appendingPathComponent(model.fileName)
    }

    static func isDownloaded(_ model: ModelSize) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: model).path)
    }

    /// Downloads and verifies the model, reporting progress in 0...1.
    static func download(
        _ model: ModelSize,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let progressDelegate = ProgressDelegate(onProgress: progress)
        let (tempURL, _) = try await URLSession.shared.download(
            from: model.downloadURL,
            delegate: progressDelegate
        )

        let digest = try sha256Hex(of: tempURL)
        guard digest == model.sha256 else {
            try? FileManager.default.removeItem(at: tempURL)
            throw ModelStoreError.hashMismatch
        }

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let destination = localURL(for: model)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    private static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        let chunkSize = 4 * 1024 * 1024
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private final class ProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let onProgress: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted) { [onProgress] progress, _ in
            onProgress(progress.fractionCompleted)
        }
    }
}
