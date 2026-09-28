import Foundation
import os

private let logger = Logger(subsystem: "com.butler", category: "LLM")

/// Drives a local llama.cpp model.
///
/// Thread-safety strategy: all mutation of `isLoaded` and calls into
/// `LlamaWrapper` are serialised through `inferenceQueue`. The class
/// no longer claims `@unchecked Sendable`; instead callers go through
/// `async` entry points that hop to the queue as needed.
final class LocalLLMEngine: LLMEngine, Sendable {
    private let wrapper = LlamaWrapper()
    private let config = LLMConfiguration()
    // nonisolated(unsafe) is safe here: every access is serialised
    // through inferenceQueue below.
    nonisolated(unsafe) private var isLoaded = false
    private let inferenceQueue = DispatchQueue(label: "com.butler.llmQueue", qos: .userInitiated)

    func load() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            inferenceQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: AssistantError.inferenceFailed("Engine deallocated before load"))
                    return
                }
                guard !self.isLoaded else {
                    continuation.resume()
                    return
                }

                let modelPath = self.config.getModelPath()
                guard !modelPath.isEmpty, FileManager.default.fileExists(atPath: modelPath) else {
                    logger.error("Model not found at path: \(modelPath)")
                    continuation.resume(throwing: AssistantError.modelNotFound("LLM model not found at path: \(modelPath)"))
                    return
                }

                do {
                    logger.info("Loading model from \(modelPath)")
                    let startTime = Date()

                    if let visionPath = self.config.getVisionModelPath(),
                       FileManager.default.fileExists(atPath: visionPath) {
                        logger.info("Loading vision projector from \(visionPath)")
                        do {
                            try self.wrapper.loadVisionModel(modelPath, mmprojPath: visionPath, contextSize: Int32(self.config.contextSize))
                        } catch {
                            logger.warning("Vision projector load failed — falling back to text-only: \(error.localizedDescription)")
                            try self.wrapper.loadModel(modelPath, contextSize: Int32(self.config.contextSize))
                        }
                    } else {
                        try self.wrapper.loadModel(modelPath, contextSize: Int32(self.config.contextSize))
                    }

                    let elapsed = String(format: "%.2f", Date().timeIntervalSince(startTime))
                    logger.info("Model loaded in \(elapsed)s")
                } catch {
                    logger.error("Failed to load model: \(error.localizedDescription)")
                    continuation.resume(throwing: AssistantError.modelNotFound(error.localizedDescription))
                    return
                }

                self.isLoaded = true

                // Restore binary project memory if available.
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let binaryPath = docs.appendingPathComponent("butler_project_memory.bin").path
                if FileManager.default.fileExists(atPath: binaryPath) {
                    logger.info("Found existing binary project memory — loading...")
                    do {
                        try self.wrapper.loadState(fromPath: binaryPath)
                        logger.info("Binary project memory loaded successfully")
                    } catch {
                        logger.warning("Could not load binary project memory: \(error.localizedDescription)")
                    }
                }

                continuation.resume()
            }
        }
    }

    func unload() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            inferenceQueue.async { [weak self] in
                self?.wrapper.unload()
                self?.isLoaded = false
                continuation.resume()
            }
        }
    }

    func generateStreaming(prompt: String, onToken: @escaping (String) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            inferenceQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: AssistantError.inferenceFailed("Engine deallocated"))
                    return
                }
                guard self.isLoaded else {
                    logger.error("generateStreaming called before model is loaded")
                    continuation.resume(throwing: AssistantError.inferenceFailed("Model not loaded"))
                    return
                }

                logger.debug("Starting generation")
                var tokenCount = 0
                let startTime = Date()

                self.wrapper.generateStreaming(prompt,
                                               temperature: self.config.temperature,
                                               maxTokens: Int32(self.config.maxTokens)) { token in
                    tokenCount += 1
                    onToken(token)
                }

                let duration = Date().timeIntervalSince(startTime)
                let tps = duration > 0 ? Double(tokenCount) / duration : 0
                logger.info("Generated \(tokenCount) tokens in \(String(format: "%.2f", duration))s (\(String(format: "%.1f", tps)) tok/s)")
                continuation.resume()
            }
        }
    }

    func generateVisionStreaming(prompt: String, imagePath: String, onToken: @escaping (String) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            inferenceQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: AssistantError.inferenceFailed("Engine deallocated"))
                    return
                }
                guard self.isLoaded else {
                    logger.error("generateVisionStreaming called before model is loaded")
                    continuation.resume(throwing: AssistantError.inferenceFailed("Model not loaded"))
                    return
                }

                logger.debug("Starting vision generation for \(imagePath)")
                var tokenCount = 0
                let startTime = Date()

                self.wrapper.generateVisionStreaming(prompt,
                                                     imagePath: imagePath,
                                                     temperature: self.config.temperature,
                                                     maxTokens: Int32(self.config.maxTokens)) { token in
                    tokenCount += 1
                    onToken(token)
                }

                let duration = Date().timeIntervalSince(startTime)
                let tps = duration > 0 ? Double(tokenCount) / duration : 0
                logger.info("Vision: generated \(tokenCount) tokens in \(String(format: "%.2f", duration))s (\(String(format: "%.1f", tps)) tok/s)")
                continuation.resume()
            }
        }
    }

    func saveState(to path: String, prompt: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            inferenceQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: AssistantError.inferenceFailed("Engine deallocated"))
                    return
                }
                guard self.isLoaded else {
                    continuation.resume(throwing: AssistantError.inferenceFailed("Model not loaded"))
                    return
                }

                logger.info("Saving binary memory state to \(path)")
                do {
                    try self.wrapper.saveState(toPath: path, prompt: prompt)
                    logger.info("Binary memory state saved successfully")
                    continuation.resume()
                } catch {
                    logger.error("Failed to save binary memory state: \(error.localizedDescription)")
                    continuation.resume(throwing: AssistantError.inferenceFailed(error.localizedDescription))
                }
            }
        }
    }

    func loadState(from path: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            inferenceQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: AssistantError.inferenceFailed("Engine deallocated"))
                    return
                }
                guard self.isLoaded else {
                    continuation.resume(throwing: AssistantError.inferenceFailed("Model not loaded"))
                    return
                }

                logger.info("Loading binary memory state from \(path)")
                do {
                    try self.wrapper.loadState(fromPath: path)
                    logger.info("Binary memory state loaded")
                    continuation.resume()
                } catch {
                    logger.error("Failed to load binary memory state: \(error.localizedDescription)")
                    continuation.resume(throwing: AssistantError.inferenceFailed(error.localizedDescription))
                }
            }
        }
    }

    func cancel() {
        wrapper.cancel()
    }
}
