import SwiftUI

struct ButtonWithStatusIndicator: View {
    let title: String
    let action: () -> Void
    let isLoading: Bool
    let hasError: Bool
    let errorMessage: String?
    let successMessage: String
    let isSuccess: Bool

    @State private var loadingIconIndex = 0
    private let loadingIcons = ["play.fill"]
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Image(
                    systemName: isLoading ? loadingIcons[loadingIconIndex] : (hasError ? "stop.fill" : "circle.fill")
                )
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .antialiased(true)
                .foregroundColor(iconColor)
                .frame(width: 10, height: 10)
                .shadow(color: iconColor, radius: 2, x: 0, y: 0)
                .animation(.easeInOut(duration: 0.3), value: loadingIconIndex)
                .animation(.easeInOut(duration: 0.3), value: isLoading)
                .animation(.easeInOut(duration: 0.3), value: hasError)
                .padding(.top, 2)
            }
        }
        .help(hasError ? (errorMessage ?? "Error occurred") : successMessage)
        .onReceive(timer) { _ in
            if isLoading {
                loadingIconIndex = (loadingIconIndex + 1) % loadingIcons.count
            }
        }
    }
    
    private var iconColor: Color {
        if isLoading {
            return .yellow
        } else if hasError {
            return .red
        } else if isSuccess {
            return .green
        }
        return .gray
    }
}
