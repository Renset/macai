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
    static let chatGptDefaultModel = "gpt-3.5-turbo"
    static let chatGptContextSize: Double = 10
    static let chatGptSystemMessage: String = String(format: "You are ChatGPT, a large language model trained by OpenAI. Answer as concisely as possible. Knowledge cutoff: 2021-09-01. Current date: %@", getCurrentFormattedDate())
}

func getCurrentFormattedDate() -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    return dateFormatter.string(from: Date())
}
