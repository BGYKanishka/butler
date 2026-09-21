import Foundation
import Combine

struct SubtitleItem: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

class OverlayViewModel: ObservableObject {
    @Published var subtitles: [SubtitleItem] = []
    @Published var detectedQuestion: String? = nil
    @Published var llmResponse: String? = nil
    @Published var latency: TimeInterval? = nil
    @Published var statusText: String = "Listening"
    
    private var questionDetectedTime: Date? = nil
    
    func appendSubtitle(_ text: String) {
        let item = SubtitleItem(text: text)
        subtitles.append(item)
        if subtitles.count > 3 {
            subtitles.removeFirst()
        }
        
        let itemId = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self else { return }
            if let index = self.subtitles.firstIndex(where: { $0.id == itemId }) {
                self.subtitles.remove(at: index)
            }
        }
    }
    
    func setQuestion(_ question: String) {
        detectedQuestion = question
        llmResponse = nil
        latency = nil
        statusText = "Processing"
        questionDetectedTime = Date()
    }
    
    func appendLLMToken(_ token: String) {
        if llmResponse == nil {
            llmResponse = ""
            if let startTime = questionDetectedTime {
                latency = Date().timeIntervalSince(startTime)
            }
            statusText = "Answering"
        }
        llmResponse? += token
    }
    
    func clearLLMResponse() {
        llmResponse = nil
        detectedQuestion = nil
        latency = nil
        statusText = "Listening"
    }
}
