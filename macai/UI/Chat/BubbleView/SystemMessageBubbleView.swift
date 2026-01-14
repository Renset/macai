import SwiftUI

struct SystemMessageBubbleView: View {
    let message: String
    let color: String?
    @Binding var newMessage: String
    @Binding var editSystemMessage: Bool
    @Binding var searchText: String
    
    var body: some View {
        ChatBubbleView(
            content: ChatBubbleContent(
                message: message,
                own: true,
                waitingForResponse: false,
                errorMessage: nil,
                systemMessage: true,
                isStreaming: false,
                isLatestMessage: false,
                reasoningDuration: nil,
                isActiveReasoning: false
            ),
            color: color,
            onEdit: {
                editSystemMessage = true
                newMessage = message
            },
            searchText: $searchText
        )
    }
}
