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

    /// The pin is part of the name, so bumping a revision never reuses a stale file.
    var localFileName: String {
        "\(sha256.prefix(12))-\(fileName)"
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
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .hashMismatch:
            return "Downloaded model failed its SHA-256 check and was deleted."
        case .httpStatus(let code):
            return "Download failed (HTTP \(code))."
        }
    }
}

enum ModelStore {
    /// Models live here. The first access moves the directory used under the
    /// old "konjac" name, if there is one; launch forces that access.
    static let directory: URL = {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let legacy = support.appendingPathComponent("konjac", isDirectory: true)
        let current = support.appendingPathComponent("Konnyaku", isDirectory: true)
        LegacyMigration.moveDirectory(from: legacy, to: current)
        return current
    }()

    static func localURL(for model: ModelSize) -> URL {
        directory.appendingPathComponent(model.localFileName)
    }

    static func isDownloaded(_ model: ModelSize) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: model).path)
    }

    /// Downloads and verifies the model, reporting progress in 0...1.
    /// `onVerifying` fires once the download ends, before the SHA-256 pass.
    static func download(
        _ model: ModelSize,
        progress: @escaping @Sendable (Double) -> Void,
        onVerifying: @escaping @Sendable () -> Void
    ) async throws -> URL {
        let progressDelegate = ProgressDelegate(onProgress: progress)
        defer { progressDelegate.stop() }
        let (tempURL, response) = try await URLSession.shared.download(
            from: model.downloadURL,
            delegate: progressDelegate
        )

        // After a successful move this finds nothing and is ignored.
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            throw ModelStoreError.httpStatus(statusCode)
        }

        progress(1.0)
        onVerifying()
        let digest = try sha256Hex(of: tempURL)
        guard digest == model.sha256 else {
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

/// Reports download progress, at most once per percentage point.
private final class ProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private static let minimumStep = 0.01

    let onProgress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var observation: NSKeyValueObservation?
    private var lastReported = 0.0

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        let newObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            self?.report(progress.fractionCompleted)
        }
        lock.lock()
        observation = newObservation
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        stop()
    }

    func stop() {
        lock.lock()
        observation?.invalidate()
        observation = nil
        lock.unlock()
    }

    private func report(_ fraction: Double) {
        lock.lock()
        let isFinished = observation == nil
        let step = fraction - lastReported
        let shouldReport = !isFinished && step >= Self.minimumStep
        if shouldReport {
            lastReported = fraction
        }
        lock.unlock()

        if shouldReport {
            onProgress(fraction)
        }
    }
}
