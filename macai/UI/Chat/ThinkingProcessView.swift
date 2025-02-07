import SwiftUI

struct ThinkingProcessView: View {
    let content: String
    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Text("Reasoning")
                        .foregroundColor(.gray)

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.gray)
                        .font(.system(size: 12))

                    Spacer()
                }
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                Text(content)
                    .foregroundColor(.gray)
                    .padding(.leading, 24)
                    .transition(.opacity)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 8)
    }
}
