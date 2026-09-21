import Foundation

class TranscriptStore {
    private var segments: [TranscriptSegment] = []
    
    func store(_ segment: TranscriptSegment) {
        segments.append(segment)
        if segments.count > 100 {
            segments.removeFirst(segments.count - 100)
        }
    }
    
    func getAll() -> [TranscriptSegment] {
        return segments
    }
}
