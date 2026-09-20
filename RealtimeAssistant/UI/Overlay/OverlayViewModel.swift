import Foundation
import Combine

class OverlayViewModel: ObservableObject {
    @Published var subtitles: [String] = []
    @Published var llmResponse: String? = nil
    @Published var isListening: Bool = false
    @Published var isAnswering: Bool = false
    
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
    
    func appendLLMToken(_ token: String) {
        if llmResponse == nil {
            llmResponse = ""
            isAnswering = true
        }
        llmResponse? += token
    }
    
    func clearLLMResponse() {
        llmResponse = nil
        isAnswering = false
    }
}
