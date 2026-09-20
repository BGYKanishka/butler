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
        "how would you handle"
    ]
    
    func detect(transcript: String, source: AudioSource) -> QuestionDetectionResult {
        // Only process REMOTE transcripts
        guard source == .system else { return .none }
        
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
