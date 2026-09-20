import Foundation

class PromptBuilder {
    func build(context: String, question: String) -> String {
        return """
        System: You are a concise meeting assistant. Answer the current question directly.
        Do not repeat the question. Be accurate. Give concise examples. Max ~150 tokens.
        
        Recent conversation:
        \(context)
        
        Current question: \(question)
        
        Answer:
        """
    }
}
