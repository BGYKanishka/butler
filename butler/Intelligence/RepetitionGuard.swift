import Foundation

/// Detects a model that has fallen into a loop so the generation can be cancelled instead of burning
/// the rest of the token budget on text the user has already read.
///
/// Why n-grams and not "same sentence twice": the loops in real Butler logs are NEAR-duplicates
/// ("The `llm_graph_params` object is used to specify the parameters for the graph, such as the model
/// and ..." repeated with small wording changes). Exact sentence matching misses them. Here a loop is
/// reported when a long consecutive stretch of words consists only of 8-word sequences that were
/// already produced earlier in the same answer. Short repeated phrases and normal bullet lists never
/// reach that threshold.
///
/// The sampler also applies a repetition penalty; this is the second line of defence.
struct RepetitionGuard {
    private var pending = ""
    private var words = [String]()
    private var seenGrams = Set<String>()
    private var run = 0
    private let gramSize: Int
    private let maxRun: Int

    /// - Parameters:
    ///   - gramSize: number of consecutive words that form one fingerprint.
    ///   - maxRun: how many consecutive already-seen fingerprints count as a loop.
    init(gramSize: Int = 8, maxRun: Int = 8) {
        self.gramSize = gramSize
        self.maxRun = maxRun
    }

    /// Feed the next streamed token. Returns `true` once the output is clearly looping.
    mutating func shouldStop(after token: String) -> Bool {
        pending += token
        var looping = false
        while let idx = pending.firstIndex(where: { $0.isWhitespace }) {
            let raw = String(pending[..<idx])
            pending.removeSubrange(...idx)
            let word = RepetitionGuard.normalize(raw)
            guard !word.isEmpty else { continue }
            words.append(word)
            guard words.count >= gramSize else { continue }

            let gram = words.suffix(gramSize).joined(separator: " ")
            if seenGrams.insert(gram).inserted {
                run = 0
            } else {
                run += 1
                if run >= maxRun { looping = true }
            }
            if words.count > 64 { words.removeFirst(words.count - gramSize) }
        }
        return looping
    }

    static func normalize(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
