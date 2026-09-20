import Foundation

class TranscriptStore {
    private var segments: [TranscriptSegment] = []
    
    func store(_ segment: TranscriptSegment) {
        segments.append(segment)
    }
    
    func getAll() -> [TranscriptSegment] {
        return segments
    }
}
