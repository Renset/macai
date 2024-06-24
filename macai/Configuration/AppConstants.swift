//
//  AppConstants.swift
//  macai
//
//  Created by Renat Notfullin on 29.03.2023.
//

import Foundation

struct AppConstants {
    static let requestTimeout: TimeInterval = 180
    static let apiUrlChatCompletions: String = "https://api.openai.com/v1/chat/completions"
    static let chatGptDefaultModel = "gpt-4o"
    static let chatGptContextSize: Double = 10
    static let chatGptSystemMessage: String = String(format: "You are ChatGPT, a large language model trained by OpenAI. Answer as concisely as possible. Knowledge cutoff: 2023-10-01. Current date: %@", getCurrentFormattedDate())
    static let chatGptGenerateChatInstruction: String = "Return a short chat name as summary for this chat based on the previous message content and system message if it's not default. Start chat name with one appropriate emoji. Don't answer to my message, just generate a name."
    static let longStringCount = 1000
}

func getCurrentFormattedDate() -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    return dateFormatter.string(from: Date())
}
