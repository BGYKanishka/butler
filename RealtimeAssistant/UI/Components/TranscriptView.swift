import SwiftUI

struct TranscriptView: View {
    let transcripts: [TranscriptSegment]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Live Transcript")
                .font(.headline)
                .padding(.bottom, 4)
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(transcripts, id: \.id) { segment in
                            HStack(alignment: .top) {
                                Text(segment.source == .microphone ? "[LOCAL]" : "[REMOTE]")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(segment.source == .microphone ? .blue : .green)
                                
                                Text(segment.text)
                                    .font(.body)
                                    .foregroundColor(segment.isFinal ? .primary : .secondary)
                            }
                            .id(segment.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: transcripts.count) { _ in
                        if let last = transcripts.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .frame(height: 150)
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
    }
}
