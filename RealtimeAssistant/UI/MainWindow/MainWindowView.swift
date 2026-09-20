import SwiftUI

struct MainWindowView: View {
    var body: some View {
        VStack {
            Text("RealtimeAssistant Session Control")
                .font(.largeTitle)
                .padding()
            
            HStack {
                Button("Start Session") {
                    // Start session logic here
                }
                
                Button("Stop Session") {
                    // Stop session logic here
                }
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}
