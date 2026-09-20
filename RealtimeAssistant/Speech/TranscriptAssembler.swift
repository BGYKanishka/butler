import Foundation

class TranscriptAssembler {
    private var segments: [TranscriptSegment] = []
    
    func addSegment(_ segment: TranscriptSegment) {
        segments.append(segment)
        // Deduplication logic goes here
    }
    
    func getTranscriptText() -> String {
        return segments.map { $0.text }.joined(separator: " ")
    }
}
