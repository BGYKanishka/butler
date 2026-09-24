import Foundation

class PromptBuilder {
    func build(context: String, question: String, source: AudioSource) -> String {
        let sourceStr = source == .microphone ? "Microphone (The user talking)" : "System Audio (A video, meeting, or app playing on the computer)"
        return """
        <|im_start|>system
        You are a smart meeting assistant. 
        Read the recent conversation and the current transcript.
        The current transcript you are analyzing came from: \(sourceStr)
        If the current transcript is directed at you, asking ANY question (even casual ones like "what is going on?"), or stating a problem that needs assistance, you MUST start your response with "YES|" and then provide the answer.
        If it is clearly just background conversation between other people that does not require your input, you MUST output ONLY "NO" and nothing else.
        <|im_end|>
        <|im_start|>user
        Recent conversation:
        \(context)
        
        Current transcript [Source: \(sourceStr)]: \(question)<|im_end|>
        <|im_start|>assistant
        """
    }
}
