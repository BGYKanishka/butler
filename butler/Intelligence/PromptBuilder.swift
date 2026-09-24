import Foundation

class PromptBuilder {
    func build(context: String, question: String) -> String {
        return """
        <|im_start|>system
        You are a smart meeting assistant. 
        Read the recent conversation and the current transcript.
        If the current transcript is directed at you, asking ANY question (even casual ones like "what is going on?"), or stating a problem that needs assistance, you MUST start your response with "YES|" and then provide the answer.
        If it is clearly just background conversation between other people that does not require your input, you MUST output ONLY "NO" and nothing else.
        <|im_end|>
        <|im_start|>user
        Recent conversation:
        \(context)
        
        Current transcript: \(question)<|im_end|>
        <|im_start|>assistant
        """
    }
}
