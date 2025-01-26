import SwiftUI

struct SystemMessageBubbleView: View {
    let message: String
    let color: String?
    @Binding var newMessage: String
    @Binding var editSystemMessage: Bool
    
    var body: some View {
        ChatBubbleView(
            content: ChatBubbleContent(
                message: message,
                own: true,
                waitingForResponse: false,
                errorMessage: nil,
                systemMessage: true,
                isStreaming: false
            ),
            color: color,
            onEdit: {
                newMessage = message
                editSystemMessage = true
            }
        )
    }
}
