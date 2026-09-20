import Foundation

class TranscriptAssembler {
    private var segments: [TranscriptSegment] = []
    
    func addSegment(_ segment: TranscriptSegment) {
        if segments.isEmpty {
            segments.append(segment)
            return
        }
        
        let lastSegment = segments.last!
        
        // Only attempt to deduplicate if from the same source
        guard lastSegment.source == segment.source else {
            segments.append(segment)
            return
        }
        
        let mergedText = mergeOverlappingStrings(s1: lastSegment.text, s2: segment.text)
        
        if mergedText != lastSegment.text + " " + segment.text {
            // There was overlap, update the last segment
            let newSegment = TranscriptSegment(
                id: lastSegment.id,
                source: lastSegment.source,
                startTime: lastSegment.startTime,
                endTime: segment.endTime,
                text: mergedText,
                isFinal: segment.isFinal,
                confidence: segment.confidence
            )
            segments[segments.count - 1] = newSegment
        } else {
            // No overlap, just append
            segments.append(segment)
        }
    }
    
    func getTranscriptText() -> String {
        return segments.map { $0.text }.joined(separator: " ")
    }
    
    private func mergeOverlappingStrings(s1: String, s2: String) -> String {
        let clean1 = s1.trimmingCharacters(in: .whitespacesAndNewlines)
        let clean2 = s2.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let words1 = clean1.split(separator: " ").map { String($0) }
        let words2 = clean2.split(separator: " ").map { String($0) }
        
        var maxOverlap = 0
        let minLen = min(words1.count, words2.count)
        
        for i in 1...minLen {
            let suffix = words1.suffix(i)
            let prefix = words2.prefix(i)
            
            // Compare lowercase to be safe
            if suffix.map({ $0.lowercased() }) == prefix.map({ $0.lowercased() }) {
                maxOverlap = i
            }
        }
        
        if maxOverlap > 0 {
            let nonOverlappingWords2 = words2.dropFirst(maxOverlap)
            return (words1 + nonOverlappingWords2).joined(separator: " ")
        }
        
        return clean1 + " " + clean2
    }
}
