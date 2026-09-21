import Foundation

class PromptBuilder {
    func build(context: String, question: String) -> String {
        return """
        <|im_start|>system
        You are a concise meeting assistant. Answer the current question directly.
        Do not repeat the question. Be accurate. Give concise examples. Max ~150 tokens.<|im_end|>
        <|im_start|>user
        Recent conversation:
        \(context)
        
        Current question: \(question)<|im_end|>
        <|im_start|>assistant
        """
    }
}
