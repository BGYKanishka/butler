import Foundation
import Combine

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
    }

    private var queue: [ModelFile] = []
    
    func startDownload(completion: @escaping () -> Void, error: @escaping (Error) -> Void) {
        guard let modelsDir = Constants.modelsDirectory else { return }
        let whisperDir = modelsDir.appendingPathComponent("whisper")
        let llmDir = modelsDir.appendingPathComponent("llm")
        
        try? FileManager.default.createDirectory(at: whisperDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: llmDir, withIntermediateDirectories: true)
        
        self.queue = [
            ModelFile(url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin")!, destinationDir: whisperDir, filename: "ggml-small.en.bin"),
            ModelFile(url: URL(string: "https://huggingface.co/bartowski/Qwen_Qwen2.5-VL-7B-Instruct-GGUF/resolve/main/Qwen_Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf")!, destinationDir: llmDir, filename: "Qwen_Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf"),
            ModelFile(url: URL(string: "https://huggingface.co/bartowski/Qwen_Qwen2.5-VL-7B-Instruct-GGUF/resolve/main/mmproj-Qwen_Qwen2.5-VL-7B-Instruct-f16.gguf")!, destinationDir: llmDir, filename: "mmproj-Qwen_Qwen2.5-VL-7B-Instruct-f16.gguf")
        ]
        
        // Filter out existing files
        self.queue = self.queue.filter { !FileManager.default.fileExists(atPath: $0.destinationDir.appendingPathComponent($0.filename).path) }
        
        if self.queue.isEmpty {
            completion()
            return
        }
        
        self.onComplete = completion
        self.onError = error
        DispatchQueue.main.async {
            self.isDownloading = true
        }
        self.downloadNext()
    }
    
    private func downloadNext() {
        guard let next = queue.first else {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.onComplete?()
            }
            return
        }
        
        DispatchQueue.main.async {
            self.progress = 0
            self.totalBytesWritten = 0
            self.totalBytesExpected = 1
            self.statusText = "Downloading \(next.filename)..."
        }
        
        downloadTask = downloadSession.downloadTask(with: next.url)
        downloadTask?.resume()
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        DispatchQueue.main.async {
            self.totalBytesWritten = totalBytesWritten
            self.totalBytesExpected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : 1
            self.progress = Double(self.totalBytesWritten) / Double(self.totalBytesExpected)
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let current = self.queue.first else { return }
        let destinationURL = current.destinationDir.appendingPathComponent(current.filename)
        
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
            DispatchQueue.main.async {
                self.isDownloading = false
                self.onError?(error)
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.onError?(error)
            }
        }
    }
}
