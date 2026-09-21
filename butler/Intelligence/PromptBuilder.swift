import Foundation

class PromptBuilder {
    func build(context: String, question: String) -> String {
        return """
        <|begin_of_text|><|start_header_id|>system<|end_header_id|>
        
        You are a concise meeting assistant. Answer the current question directly.
        Do not repeat the question. Be accurate. Give concise examples. Max ~150 tokens.<|eot_id|><|start_header_id|>user<|end_header_id|>
        
        Recent conversation:
        \(context)
        
        Current question: \(question)<|eot_id|><|start_header_id|>assistant<|end_header_id|>
        
        """
    }
}
