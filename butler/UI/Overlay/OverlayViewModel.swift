import Foundation
import Combine

class OverlayViewModel: ObservableObject {
    @Published var subtitles: [String] = []
    @Published var detectedQuestion: String? = nil
    @Published var llmResponse: String? = nil
    @Published var latency: TimeInterval? = nil
    @Published var statusText: String = "Listening"
    
    private var questionDetectedTime: Date? = nil
    
    func appendSubtitle(_ text: String) {
        subtitles.append(text)
        if subtitles.count > 3 {
            subtitles.removeFirst()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if let index = self.subtitles.firstIndex(of: text) {
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
