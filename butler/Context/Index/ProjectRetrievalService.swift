import Foundation

protocol ProjectRetrievalService: Sendable {
    func context(for text: String, recentTurns: [ConversationTurn],
                 isFinal: Bool, budgetTokens: Int) async -> String   // "" on any failure/timeout
}
