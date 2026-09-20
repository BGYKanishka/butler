import SwiftUI

struct AudioLevelView: View {
    var level: Float
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                
                Rectangle()
                    .fill(Color.green)
                    .frame(width: min(CGFloat(level) * geometry.size.width * 5.0, geometry.size.width))
                    .animation(.linear(duration: 0.1), value: level)
            }
        }
        .frame(height: 10)
        .cornerRadius(5)
    }
}
