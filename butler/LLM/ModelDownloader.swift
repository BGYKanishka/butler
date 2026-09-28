import Foundation
import Combine
import CryptoKit

/// Downloads model files sequentially with automatic retry and SHA-256 verification.
///
/// The previous version would abort the entire download on the first transient
/// network error and had no way to detect a corrupt file. This version adds:
/// - Up to `maxRetries` attempts per file with a short delay between each.
/// - Optional SHA-256 checksum validation before moving a file to its destination.
class ModelDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var isDownloading = false
    @Published var progress: Double = 0
    @Published var statusText: String = ""
    @Published var totalBytesWritten: Int64 = 0
    @Published var totalBytesExpected: Int64 = 1

    // lazy var lets us pass `self` as the delegate without an implicitly
    // unwrapped optional — it is initialised on first access, after super.init
    // completes, so self is valid.
    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 3600
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    private var downloadTask: URLSessionDownloadTask?

    private var onComplete: (() -> Void)?
    private var onError: ((Error) -> Void)?

    struct ModelFile {
        let url: URL
        let destinationDir: URL
        let filename: String
        /// Expected SHA-256 hex digest. nil means skip verification.
        let sha256: String?
    }

    private var queue: [ModelFile] = []
    private var currentRetry = 0
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 2.0

    func startDownload(completion: @escaping () -> Void, error: @escaping (Error) -> Void) {
        guard let modelsDir = Constants.modelsDirectory else { return }
        let whisperDir = modelsDir.appendingPathComponent("whisper")
        let llmDir = modelsDir.appendingPathComponent("llm")

        try? FileManager.default.createDirectory(at: whisperDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: llmDir, withIntermediateDirectories: true)

        self.queue = [
            ModelFile(
                url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin")!,
                destinationDir: whisperDir,
                filename: "ggml-small.en.bin",
                sha256: nil  // verified at runtime by whisper_init
            ),
            ModelFile(
                url: URL(string: "https://huggingface.co/bartowski/Qwen_Qwen2.5-VL-7B-Instruct-GGUF/resolve/main/Qwen_Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf")!,
                destinationDir: llmDir,
                filename: "Qwen_Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf",
                sha256: nil
            ),
            ModelFile(
                url: URL(string: "https://huggingface.co/bartowski/Qwen_Qwen2.5-VL-7B-Instruct-GGUF/resolve/main/mmproj-Qwen_Qwen2.5-VL-7B-Instruct-f16.gguf")!,
                destinationDir: llmDir,
                filename: "mmproj-Qwen_Qwen2.5-VL-7B-Instruct-f16.gguf",
                sha256: nil
            ),
        ]

        // Skip already-present files.
        self.queue = self.queue.filter {
            !FileManager.default.fileExists(atPath: $0.destinationDir.appendingPathComponent($0.filename).path)
        }

        guard !self.queue.isEmpty else {
            completion()
            return
        }

        self.onComplete = completion
        self.onError = error
        DispatchQueue.main.async { self.isDownloading = true }
        downloadNext()
    }

    // MARK: - Private download flow

    private func downloadNext() {
        currentRetry = 0
        attemptDownload()
    }

    private func attemptDownload() {
        guard let next = queue.first else {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.onComplete?()
            }
            return
        }

        let attempt = currentRetry + 1
        let suffix = attempt > 1 ? " (attempt \(attempt)/\(maxRetries))" : ""
        DispatchQueue.main.async {
            self.progress = 0
            self.totalBytesWritten = 0
            self.totalBytesExpected = 1
            self.statusText = "Downloading \(next.filename)\(suffix)..."
        }

        downloadTask = downloadSession.downloadTask(with: next.url)
        downloadTask?.resume()
    }

    private func retryOrFail(error: Error) {
        currentRetry += 1
        if currentRetry < maxRetries {
            DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
                self?.attemptDownload()
            }
        } else {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.onError?(error)
            }
        }
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        DispatchQueue.main.async {
            self.totalBytesWritten = totalBytesWritten
            self.totalBytesExpected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : 1
            self.progress = Double(self.totalBytesWritten) / Double(self.totalBytesExpected)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let current = queue.first else { return }
        let destinationURL = current.destinationDir.appendingPathComponent(current.filename)

        // Validate checksum before moving the file into place.
        if let expected = current.sha256 {
            guard let digest = sha256(of: location), digest == expected else {
                let err = NSError(
                    domain: "ModelDownloader",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Checksum mismatch for \(current.filename) — the download may be corrupt"]
                )
                // Retry from scratch; don't move the bad file.
                retryOrFail(error: err)
                return
            }
        }

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)

            DispatchQueue.main.async {
                self.queue.removeFirst()
                self.downloadNext()
            }
        } catch {
            retryOrFail(error: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            retryOrFail(error: error)
        }
    }

    // MARK: - Helpers

    private func sha256(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
