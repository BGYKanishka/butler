import Foundation

let prompt = """
<|im_start|>system
You are a smart meeting assistant. 
Read the recent conversation and the current transcript.
If the current transcript is asking a direct question or stating a problem that needs assistance, you MUST start your response with "YES|" and then provide the answer.
If it is just normal conversation, a statement, or background noise, you MUST output ONLY "NO" and nothing else.
<|im_end|>
<|im_start|>user
Recent conversation:
[LOCAL]:  So, you only can get the input from mic, right.

Current transcript:  So, you only can get the input from mic, right.<|im_end|>
<|im_start|>assistant
"""
print(prompt)
