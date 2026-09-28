import Foundation
import Combine
import AVFoundation
import AppKit
import os

private let logger = Logger(subsystem: "com.butler", category: "Session")

/// Coordinates the full session lifecycle: audio capture → speech-to-text → LLM response.
///
/// Pinned to the main actor because every property it exposes (`state`, `transcripts`,
/// etc.) drives SwiftUI and must be mutated on the main thread. This lets the compiler
/// enforce that rule rather than relying on scattered DispatchQueue.main.async calls.
@MainActor
final class SessionCoordinator: ObservableObject {
    let environment: AppEnvironment

    var micService: MicrophoneCaptureService { environment.micService }
    var sysAudioService: SystemAudioCaptureService { environment.sysAudioService }
    var audioSessionCoordinator: AudioSessionCoordinator { environment.audioSessionCoordinator }
    var whisperEngine: WhisperEngine { environment.whisperEngine }
    var llmEngine: LLMEngine { environment.llmEngine }
    var contextManager: ContextManager { environment.contextManager }
    var promptBuilder: PromptBuilder { environment.promptBuilder }
    var transcriptAssembler: TranscriptAssembler { environment.transcriptAssembler }

    lazy var responseGenerator = ResponseGenerator(
        contextManager: contextManager,
        promptBuilder: promptBuilder,
        llmEngine: llmEngine
    )

    var onHideMainWindow: (() -> Void)?
    var onShowMainWindow: (() -> Void)?
    var onShowSettings: (() -> Void)?

    @Published var modelDownloader = ModelDownloader()

    @Published var state: SessionState = .idle
    @Published var transcripts: [TranscriptSegment] = []
    @Published var isLoadingModels: Bool = false
    @Published var micAudioLevel: Float = 0.0
    @Published var sysAudioLevel: Float = 0.0
    @Published var isMicMuted: Bool = false
    @Published var isSysAudioMuted: Bool = false

    private var lastPartialEvalTime: Date = .distantPast
    private var lastAnswerEndTime: Date = .distantPast

    private var cancellables = Set<AnyCancellable>()

    init(environment: AppEnvironment = AppEnvironment()) {
        self.environment = environment
        setupBindings()
    }

    private func setupBindings() {
        modelDownloader.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        responseGenerator.onTokenGenerated = { [weak self] token in
            guard let self else { return }
            if let last = self.transcripts.last, last.source == .assistant, !last.isFinal {
                var updated = last
                updated.text += token
                self.transcripts[self.transcripts.count - 1] = updated
            } else {
                let newSeg = TranscriptSegment(
                    id: UUID(), source: .assistant,
                    startTime: Date().timeIntervalSince1970,
                    endTime: Date().timeIntervalSince1970,
                    text: token, isFinal: false, confidence: 1.0
                )
                self.transcripts.append(newSeg)
            }
        }

        responseGenerator.onResponseCompleted = { [weak self] in
            guard let self, self.state == .answering else { return }
            self.lastAnswerEndTime = Date()
            self.state = .listening

            if let last = self.transcripts.last, last.source == .assistant, !last.isFinal {
                var updated = last
                updated.isFinal = true
                self.transcripts[self.transcripts.count - 1] = updated

                let finalAnswer = updated.text
                Task {
                    let turn = ConversationTurn(id: UUID(), source: .assistant, type: .answer, text: finalAnswer, timestamp: Date())
                    await self.contextManager.addTurn(turn)
                }
            }
        }

        audioSessionCoordinator.micService.onAudioLevelChanged = { [weak self] level in
            Task { @MainActor [weak self] in self?.micAudioLevel = level }
        }

        audioSessionCoordinator.sysAudioService.onAudioLevelChanged = { [weak self] level in
            Task { @MainActor [weak self] in self?.sysAudioLevel = level }
        }

        audioSessionCoordinator.onSpeechDetected = { [weak self] samples, source in
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self, await self.sessionIsActive() else { return }
                logger.info("Speech detected from \(String(describing: source)) — transcribing")
                do {
                    try await self.whisperEngine.transcribe(samples: samples, sampleRate: 16000, source: source)
                } catch {
                    logger.error("Transcription failed: \(error.localizedDescription)")
                    await MainActor.run { self.state = .error(error) }
                }
            }
        }

        whisperEngine.onTranscriptionCompleted = { [weak self] segment in
            Task { @MainActor [weak self] in self?.handleTranscription(segment: segment) }
        }

        whisperEngine.onPartialTranscriptionCompleted = { [weak self] segment in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.state != .answering && Date().timeIntervalSince(self.lastAnswerEndTime) > 3.0 {
                    let now = Date()
                    if now.timeIntervalSince(self.lastPartialEvalTime) > 1.5 {
                        self.lastPartialEvalTime = now
                        self.responseGenerator.handleTranscript(segment.text, source: segment.source)
                    }
                }
            }
        }

        responseGenerator.onIntentConfirmed = { [weak self] question in
            guard let self else { return }
            logger.info("Intent confirmed by LLM for: \(question)")
            self.state = .answering
        }
    }

    private func handleTranscription(segment: TranscriptSegment) {
        Task {
            await transcriptAssembler.addSegment(segment)
            let turn = ConversationTurn(id: UUID(), source: segment.source, type: .statement, text: segment.text, timestamp: Date())
            await contextManager.addTurn(turn)

            transcripts.append(segment)
            if transcripts.count > 100 {
                transcripts.removeFirst(transcripts.count - 100)
            }

            if state != .answering && Date().timeIntervalSince(lastAnswerEndTime) > 3.0 {
                responseGenerator.handleTranscript(segment.text, source: segment.source)
            }
        }
    }

    private func sessionIsActive() -> Bool {
        switch state {
        case .idle, .error: return false
        default: return true
        }
    }

    func startSession() {
        switch state {
        case .idle, .error: break
        default: return
        }
        let gateway = environment.permissionsGateway
        startSessionInternal(micGranted: gateway.isMicGranted)
    }

    private func startSessionInternal(micGranted: Bool) {
        state = .listening
        isLoadingModels = true

        let modelManager = ModelManager()
        if modelManager.areModelsMissing() {
            modelDownloader.startDownload { [weak self] in
                Task { @MainActor [weak self] in
                    self?.continueStartingSession(micGranted: micGranted)
                }
            } error: { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.isLoadingModels = false
                    self?.state = .error(error)
                }
            }
        } else {
            continueStartingSession(micGranted: micGranted)
        }
    }

    private func continueStartingSession(micGranted: Bool) {
        Task {
            do {
                let modelManager = ModelManager()
                try modelManager.validateModels()

                try await whisperEngine.load()
                try await llmEngine.load()

                let _ = UserDefaults.standard.bool(forKey: ConfigKey.isVisionEnabled)
                try await audioSessionCoordinator.start(
                    includeSystemAudio: environment.permissionsGateway.isScreenGranted,
                    micGranted: micGranted
                )

                MemoryMonitor.shared.startMonitoring()
                isLoadingModels = false
                logger.info("Session started")
            } catch {
                logger.error("Failed to start session: \(error.localizedDescription)")
                isLoadingModels = false
                state = .error(error)
            }
        }
    }

    func stopSession() async {
        guard state != .idle else { return }

        audioSessionCoordinator.stop()
        whisperEngine.cancel()
        llmEngine.cancel()
        MemoryMonitor.shared.stopMonitoring()

        state = .idle
        isMicMuted = false
        isSysAudioMuted = false

        await whisperEngine.unload()
        await llmEngine.unload()

        transcripts.removeAll()
        logger.info("Session stopped")
    }

    func toggleMic() {
        if isMicMuted {
            Task {
                try? await micService.start()
                isMicMuted = false
            }
        } else {
            audioSessionCoordinator.stopMic()
            isMicMuted = true
        }
    }

    func toggleSystemAudio() {
        if isSysAudioMuted {
            Task {
                try? await sysAudioService.start()
                isSysAudioMuted = false
            }
        } else {
            audioSessionCoordinator.stopSystemAudio()
            isSysAudioMuted = true
        }
    }

    func triggerVisionAnalysis() {
        if isLoadingModels || state == .idle {
            logger.warning("Vision analysis requested but session is not active")
            return
        }
        if case .error = state {
            logger.warning("Vision analysis requested but session is in error state")
            return
        }

        onHideMainWindow?()

        InteractiveCaptureService.shared.captureRegion { [weak self] fileUrl in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.onShowMainWindow?()
                guard let imagePath = fileUrl?.path else { return }

                let recentContext = await self.contextManager.getRecentContext()
                let basePrompt = "Analyze this image. If it contains a multiple-choice question or a direct problem, state the final answer clearly in the first sentence, followed by a step-by-step solution. If it's a general image, simply explain or describe it naturally as a helpful AI assistant."
                let finalPrompt = recentContext.isEmpty
                    ? basePrompt
                    : "\(basePrompt)\n\nRecent voice/chat context:\n\(recentContext)\n\nPlease answer the user's latest query considering the image."

                self.processVisionRequest(prompt: finalPrompt, imagePath: imagePath)
            }
        }
    }

    private func processVisionRequest(prompt: String, imagePath: String) {
        state = .answering

        let userSeg = TranscriptSegment(
            id: UUID(), source: .microphone,
            startTime: Date().timeIntervalSince1970,
            endTime: Date().timeIntervalSince1970,
            text: "Image Analyzed", isFinal: true, confidence: 1.0, imagePath: imagePath
        )
        transcripts.append(userSeg)

        let aiSegId = UUID()
        let initialAiSeg = TranscriptSegment(
            id: aiSegId, source: .assistant,
            startTime: Date().timeIntervalSince1970,
            endTime: Date().timeIntervalSince1970,
            text: "", isFinal: false, confidence: 1.0
        )
        transcripts.append(initialAiSeg)

        Task {
            do {
                try await llmEngine.generateVisionStreaming(prompt: prompt, imagePath: imagePath) { [weak self] token in
                    Task { @MainActor [weak self] in
                        guard let self, let lastIdx = self.transcripts.indices.last else { return }
                        self.transcripts[lastIdx].text += token
                    }
                }

                if let lastIdx = transcripts.indices.last {
                    transcripts[lastIdx].isFinal = true
                    let finalAnswer = transcripts[lastIdx].text
                    Task {
                        let turn = ConversationTurn(id: UUID(), source: .assistant, type: .answer, text: finalAnswer, timestamp: Date())
                        await contextManager.addTurn(turn)
                    }
                }
                state = .listening
            } catch {
                logger.error("Vision analysis failed: \(error.localizedDescription)")
                state = .error(error)
            }
        }
    }
}
