import Foundation
import os

private let logger = Logger(subsystem: "com.butler", category: "Whisper")

/// Wraps the whisper.cpp transcription pipeline.
///
/// `isLoaded` and `wrapper` are only ever touched inside `transcriptionQueue`,
/// so the class no longer needs `@unchecked Sendable`. The conformance is
/// expressed through the serial queue discipline instead.
final class WhisperEngine: SpeechToTextEngine, Sendable {
    // nonisolated(unsafe): safe because every access is serialised on transcriptionQueue.
    nonisolated(unsafe) private var wrapper: WhisperWrapper?
    nonisolated(unsafe) private var isLoaded = false
    private let transcriptionQueue = DispatchQueue(label: "com.butler.whisperQueue", qos: .userInitiated)

    // Callbacks — set once from the main thread before the session starts.
    var onTranscriptionCompleted: ((TranscriptSegment) -> Void)?
    var onPartialTranscriptionCompleted: ((TranscriptSegment) -> Void)?

    func load() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            transcriptionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: AssistantError.inferenceFailed("Engine deallocated before load"))
                    return
                }
                guard !self.isLoaded else {
                    continuation.resume()
                    return
                }

                let modelPath = WhisperConfiguration().getModelPath()
                guard FileManager.default.fileExists(atPath: modelPath) else {
                    continuation.resume(throwing: AssistantError.modelNotFound("Whisper model not found at \(modelPath)"))
                    return
                }

                let w = WhisperWrapper(modelPath: modelPath)
                guard w != nil else {
                    continuation.resume(throwing: AssistantError.modelNotFound("Failed to initialise whisper context with model at \(modelPath)"))
                    return
                }

                self.wrapper = w
                self.isLoaded = true
                continuation.resume()
            }
        }
    }

    func unload() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            transcriptionQueue.async { [weak self] in
                self?.wrapper = nil   // ARC triggers whisper_free()
                self?.isLoaded = false
                continuation.resume()
            }
        }
    }

    func transcribe(samples: [Float], sampleRate: Int, source: AudioSource) async throws {
        guard !samples.isEmpty else { return }

        let result: String? = try await withCheckedThrowingContinuation { continuation in
            transcriptionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                guard let wrapper = self.wrapper else {
                    continuation.resume(throwing: AssistantError.inferenceFailed("Whisper engine not loaded"))
                    return
                }

                wrapper.onPartialTranscript = { [weak self] partialText in
                    guard let self, self.isValidTranscription(partialText) else { return }
                    let segment = TranscriptSegment(
                        id: UUID(),
                        source: source,
                        startTime: Date().timeIntervalSince1970,
                        endTime: Date().timeIntervalSince1970 + Double(samples.count) / Double(sampleRate),
                        text: partialText,
                        isFinal: false,
                        confidence: 1.0
                    )
                    self.onPartialTranscriptionCompleted?(segment)
                }

                let text = samples.withUnsafeBufferPointer { ptr in
                    let userVocab = UserDefaults.standard.string(forKey: ConfigKey.whisperVocabulary) ?? ""
                    wrapper.initialPrompt = userVocab.isEmpty ? "" : "The following terms are discussed: \(userVocab)."
                    return wrapper.transcribeAudio(ptr.baseAddress!, count: samples.count)
                }
                continuation.resume(returning: text)
            }
        }

        logger.debug("Whisper raw result: '\(result ?? "nil")'")

        if let text = result, isValidTranscription(text) {
            let segment = TranscriptSegment(
                id: UUID(),
                source: source,
                startTime: Date().timeIntervalSince1970,
                endTime: Date().timeIntervalSince1970 + Double(samples.count) / Double(sampleRate),
                text: text,
                isFinal: true,
                confidence: 1.0
            )
            onTranscriptionCompleted?(segment)
            logger.info("Transcribed: \(text)")
        } else {
            logger.debug("Ignored empty or non-speech transcription")
        }
    }

    func cancel() {
        transcriptionQueue.async { [weak self] in
            self?.wrapper?.cancelTranscription()
        }
    }

    // MARK: - Helpers

    /// Returns false for empty strings and whisper noise markers like [BLANK_AUDIO].
    ///
    /// The regex is compiled once as a `static let` — NSRegularExpression initialisation
    /// is expensive and was adding measurable overhead when called on every segment.
    private static let noiseMarkersRegex = try? NSRegularExpression(pattern: #"\[.*?\]|\(.*?\)"#, options: [])

    private func isValidTranscription(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        var cleaned = trimmed
        if let regex = WhisperEngine.noiseMarkersRegex {
            let range = NSRange(location: 0, length: cleaned.utf16.count)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        return cleaned.rangeOfCharacter(from: .alphanumerics) != nil
    }
}

extension WhisperWrapper: @unchecked Sendable {}
