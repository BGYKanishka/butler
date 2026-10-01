import Foundation

extension String {
    /// Cuts to `max` characters, preferring to stop at a line boundary.
    func clippedAtLine(to max: Int) -> String {
        guard max > 0 else { return "" }
        guard count > max else { return self }
        let hard = String(prefix(max))
        if let nl = hard.lastIndex(of: "\n"), hard.distance(from: hard.startIndex, to: nl) > max / 2 {
            return String(hard[..<nl]) + "\n…"
        }
        return hard + "…"
    }
}
