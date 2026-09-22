import Foundation

enum QuestionDetectionResult {
    case none
    case possibleQuestion
    case strongQuestion
}

class QuestionDetector {
    private let questionWords = ["what", "why", "how", "when", "where", "which", "who"]
    private let questionPhrases = [
        "can you", "could you", "explain", "describe", 
        "tell me about", "walk me through", "what would you do if", 
        "how would you handle", "is there", "are there", "do you", 
        "did you", "will you", "would you", "should we", "can we", 
        "could we", "is it possible"
    ]
    
    var onQuestionConfirmed: ((String) -> Void)?
    
    private var debounceWorkItem: DispatchWorkItem?
    
    func process(transcript: String, source: AudioSource) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Cancel any pending debounce
            self.debounceWorkItem?.cancel()
            
            let result = self.detect(transcript: transcript, source: source)
            
            if result == .strongQuestion {
                // Schedule the trigger for 500ms from now
                let workItem = DispatchWorkItem { [weak self] in
                    self?.onQuestionConfirmed?(transcript)
                }
                self.debounceWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
            }
        }
    }
    
    func detect(transcript: String, source: AudioSource) -> QuestionDetectionResult {
        // Process all transcripts, including user's voice
        if source == .microphone { return .none }

        let text = transcript.lowercased()
        
        if text.contains("?") {
            return .strongQuestion
        }
        
        for phrase in questionPhrases {
            if text.contains(phrase) {
                return .strongQuestion
            }
        }
        
        let words = text.split(separator: " ").map { String($0) }
        guard let firstWord = words.first else { return .none }
        
        if questionWords.contains(firstWord) {
            return .strongQuestion
        }
        
        for word in questionWords {
            if words.contains(word) {
                return .possibleQuestion
            }
        }
        
        return .none
    }
}
