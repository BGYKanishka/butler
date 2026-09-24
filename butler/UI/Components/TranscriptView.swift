import SwiftUI

struct TranscriptView: View {
    let transcripts: [TranscriptSegment]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live Transcript")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(transcripts, id: \.id) { segment in
                            ChatBubbleView(segment: segment)
                                .id(segment.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: transcripts.count) { oldValue, newValue in
                        if let last = transcripts.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
            )
        }
    }
}

struct ChatBubbleView: View {
    let segment: TranscriptSegment
    
    var isLocal: Bool {
        segment.source == .microphone
    }
    
    var isAssistant: Bool {
        segment.source == .assistant
    }
    
    var body: some View {
        HStack {
            if isLocal { Spacer(minLength: 40) }
            
            VStack(alignment: isLocal ? .trailing : .leading, spacing: 4) {
                Text(isLocal ? "You" : (isAssistant ? "Butler" : "Remote"))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(isAssistant ? .blue.opacity(0.8) : .secondary)
                    .padding(.horizontal, 4)
                
                Text(segment.text)
                    .font(.system(size: isAssistant ? 16 : 14, weight: .regular, design: .rounded))
                    .foregroundColor(isLocal ? .white : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isLocal ? Color.blue.opacity(0.9) : (isAssistant ? Color.blue.opacity(0.1) : Color(NSColor.windowBackgroundColor)))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isAssistant ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                    .opacity(segment.isFinal ? 1.0 : 0.6)
            }
            
            if !isLocal { Spacer(minLength: 40) }
        }
    }
}
