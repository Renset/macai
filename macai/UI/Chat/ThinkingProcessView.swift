import SwiftUI

struct ThinkingProcessView: View {
    let content: String
    let duration: TimeInterval?
    let isActive: Bool
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 2) {
                    if isActive {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 6, height: 6)
                            .modifier(PulsatingCircle())
                    }

                    Text("Reasoning")
                        .foregroundColor(.gray)

                    durationLabel()
                        .foregroundColor(.gray)

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.gray)
                        .font(.system(size: 12))

                    Spacer()
                }
            }
            .buttonStyle(PlainButtonStyle())
            .contentShape(Rectangle())

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

    @ViewBuilder
    private func durationLabel() -> some View {
        if let duration, duration >= 0 {
            Text("· \(formattedDuration(duration))")
                .monospacedDigit()
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        if duration >= 60 {
            let totalSeconds = Int(duration.rounded(.down))
            let minutes = totalSeconds / 60
            let seconds = totalSeconds % 60
            return String(format: "%dm %02ds", minutes, seconds)
        }
        if duration < 1 {
            return String(format: "%.2fs", duration)
        }
        if duration < 10 {
            return String(format: "%.1fs", duration)
        }
        return String(format: "%.0fs", duration)
    }
}
