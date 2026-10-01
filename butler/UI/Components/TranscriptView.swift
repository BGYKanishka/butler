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
                    .onChange(of: transcripts.last?.text) { oldValue, newValue in
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
                
                VStack(alignment: isLocal ? .trailing : .leading, spacing: 8) {
                    if let imagePath = segment.imagePath, let nsImage = NSImage(contentsOfFile: imagePath) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 300, maxHeight: 250)
                            .cornerRadius(8)
                    }
                    
                    Text(isAssistant ? MarkdownLite.attributed(segment.text) : AttributedString(segment.text))
                }
                    .font(.system(size: 14, weight: .regular, design: .rounded))
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


/// SwiftUI's inline-only markdown parser renders **bold** and `code` but leaves block syntax as raw
/// text, so an answer written as "- item" bullets and "## Heading" showed literal dashes and hashes.
/// This converts the block syntax Butler's prompt asks for into plain characters first.
enum MarkdownLite {
    static func attributed(_ raw: String) -> AttributedString {
        var lines = [String]()
        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let indent = String(line.prefix { $0 == " " || $0 == "\t" })
                lines.append(indent + "\u{2022}  " + String(trimmed.dropFirst(2)))
            } else if trimmed.hasPrefix("#") {
                let title = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                lines.append(title.isEmpty ? "" : "**\(title)**")
            } else {
                lines.append(line)
            }
        }
        let joined = lines.joined(separator: "\n")
        if let attributed = try? AttributedString(markdown: joined, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attributed
        }
        return AttributedString(raw)
    }
}
