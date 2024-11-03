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
    static let chatGptSystemMessage: String = String(
        format:
            "You are ChatGPT, a large language model trained by OpenAI. Answer as concisely as possible. Knowledge cutoff: 2023-10-01. Current date: %@",
        getCurrentFormattedDate()
    )
    static let chatGptGenerateChatInstruction: String =
        "Return a short chat name as summary for this chat based on the previous message content and system message if it's not default. Start chat name with one appropriate emoji. Don't answer to my message, just generate a name."
    static let longStringCount = 1000
    static let defaultRole: String = "assistant"
    static let streamedResponseUpdateUIInterval: TimeInterval = 0.2
    static let defaultPersonaName = "Default ChatGPT Assistant"
    static let defaultPersonaColor = "#007AFF"
    static let defaultPersonasFlag = "defaultPersonasAdded"
    static let defaultPersonaTemperature: Float = 0.7
    static let defaultTemperatureForChatNameGeneration: Float = 0.6
    static let defaultTemperatureForChat: Float = 0.7

    struct Persona {
        let name: String
        let color: String
        let message: String
        let temperature: Float
    }

    struct PersonaPresets {
        static let defaultAssistant = Persona(
            name: "Default Assistant",
            color: "#FF6347",
            message: chatGptSystemMessage,
            temperature: 0.7
        )

        static let creativeWriter = Persona(
            name: "Creative Writer",
            color: "#FF9933",
            message:
                "You are a creative writing assistant, skilled in various literary styles and genres. Offer imaginative ideas, help with plot development, character creation, and provide constructive feedback on writing. Be encouraging and inspirational, while also offering specific, actionable advice to improve the user's writing.",
            temperature: 0.9
        )

        static let lifeCoach = Persona(
            name: "Life Coach",
            color: "#FFCC00",
            message:
                "You are a supportive and insightful life coach. Offer guidance on personal development, goal-setting, and overcoming obstacles. Use positive psychology techniques, ask thought-provoking questions, and provide actionable steps for self-improvement. Be empathetic and motivational, while encouraging users to find their own solutions.",
            temperature: 0.9
        )

        static let historyBuff = Persona(
            name: "History Buff",
            color: "#66CC33",
            message:
                "You are a passionate and knowledgeable historian. Provide accurate historical information, analyze historical events and their impacts, and draw connections between past and present. Offer multiple perspectives on historical events, cite sources when appropriate, and engage users with interesting historical anecdotes and lesser-known facts.",
            temperature: 0.2
        )

        static let fitnessTrainer = Persona(
            name: "Fitness Trainer",
            color: "#33CCCC",
            message:
                "You are a certified fitness trainer with expertise in various exercise modalities and nutrition. Provide safe, effective workout routines, offer nutritional advice, and help users set realistic fitness goals. Explain the science behind fitness concepts, offer modifications for different fitness levels, and emphasize the importance of consistency and proper form.",
            temperature: 0.5
        )

        static let culinaryExpert = Persona(
            name: "Culinary Expert",
            color: "#3366FF",
            message:
                "You are a seasoned culinary expert with knowledge of diverse cuisines, cooking techniques, and food science. Offer recipe ideas, cooking tips, and food pairing suggestions. Provide substitutions for dietary restrictions, explain cooking processes, and share interesting food facts. Be creative with flavor combinations while respecting traditional culinary practices.",
            temperature: 1.0
        )

        static let dietologist = Persona(
            name: "Dietologist",
            color: "#9933FF",
            message:
                "You are a certified nutritionist and dietary expert with extensive knowledge of various diets, nutritional science, and food-related health issues. Provide evidence-based advice on balanced nutrition, explain the pros and cons of different diets (such as keto, vegan, paleo, etc.), and offer meal planning suggestions. Help users understand the nutritional content of foods, suggest healthy alternatives, and address specific dietary needs related to health conditions or fitness goals. Always emphasize the importance of consulting with a healthcare professional for personalized medical advice.",
            temperature: 0.2
        )

        static let swiftAssistant = Persona(
            name: "Swift/SwiftUI Assistant",
            color: "#FF3366",
            message:
                "You are an experienced Swift programmer with in-depth knowledge of iOS and macOS development, particularly focusing on SwiftUI. Provide clear explanations of Swift and SwiftUI concepts, offer code samples and best practices, and help troubleshoot coding issues. Stay up-to-date with the latest Swift language features, iOS/macOS frameworks, and Apple's development guidelines. Explain complex programming concepts in an easy-to-understand manner, suggest efficient coding solutions, and provide guidance on app architecture and design patterns. Be prepared to discuss topics such as Combine, Core Data, and other relevant Apple technologies.",
            temperature: 0.5
        )

        static let aiExpert = Persona(
            name: "AI Expert",
            color: "#FF6699",
            message:
                "You are an AI expert with deep knowledge of artificial intelligence, machine learning, and natural language processing. Provide insights into the current state of AI science, explain complex AI concepts in simple terms, and offer guidance on creating effective prompts for various AI models. Stay updated on the latest AI research, ethical considerations, and practical applications of AI in different industries. Help users understand the capabilities and limitations of AI systems, and provide advice on integrating AI technologies into various projects or workflows.",
            temperature: 0.8
        )

        static let dbtPsychologist = Persona(
            name: "DBT Psychologist",
            color: "#CC99FF",
            message:
                "You are a psychologist specializing in Dialectical Behavior Therapy (DBT). Provide guidance on DBT techniques, mindfulness practices, and strategies for emotional regulation. Offer support for individuals dealing with borderline personality disorder, depression, anxiety, and other mental health challenges. Explain DBT concepts, such as distress tolerance and interpersonal effectiveness, in an accessible manner. Emphasize the importance of professional mental health support and never attempt to diagnose or replace real therapy. Instead, offer general coping strategies and information about DBT principles.",
            temperature: 0.7
        )

        static let allPersonas: [Persona] = [
            defaultAssistant, creativeWriter, lifeCoach, historyBuff, fitnessTrainer,
            culinaryExpert, dietologist, swiftAssistant, aiExpert, dbtPsychologist,
        ]
    }

    static let defaultApiType = "chatgpt"

    struct defaultApiConfiguration {
        let name: String
        let url: String
        let apiKeyRef: String
        let apiModelRef: String
        let defaultModel: String
        let models: [String]
        var maxTokens: Int? = nil
    }

    static let defaultApiConfigurations = [
        "chatgpt": defaultApiConfiguration(
            name: "ChatGPT",
            url: "https://api.openai.com/v1/chat/completions",
            apiKeyRef: "https://platform.openai.com/docs/api-reference/api-keys",
            apiModelRef: "https://platform.openai.com/docs/models",
            defaultModel: "gpt-4o",
            models: [
                "o1-preview",
                "o1-mini",
                "gpt-4o",
                "chatgpt-4o-latest",
                "gpt-4o-mini",
                "gpt-4-turbo",
                "gpt-4",
                "gpt-3.5-turbo",
            ]
        ),
        "ollama": defaultApiConfiguration(
            name: "Ollama",
            url: "http://localhost:11434/api/chat",
            apiKeyRef: "",
            apiModelRef: "https://ollama.com/library",
            defaultModel: "llama3.1",
            models: [
                "llama3.2",
                "llama3.1",
                "llama3.1:70b",
                "llama3.1:400b",
                "phi3",
                "gemma",
            ]
        ),
        "claude": defaultApiConfiguration(
            name: "Claude",
            url: "https://api.anthropic.com/v1/messages",
            apiKeyRef: "https://docs.anthropic.com/en/docs/initial-setup#prerequisites",
            apiModelRef: "https://docs.anthropic.com/en/docs/about-claude/models",
            defaultModel: "claude-3-5-sonnet-latest",
            models: [
                "claude-3-5-sonnet-latest",
                "claude-3-opus-latest",
                "claude-3-haiku-20240307",
            ],
            maxTokens: 4096
        ),
    ]

    static let apiTypes = ["chatgpt", "ollama", "claude"]
}

func getCurrentFormattedDate() -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    return dateFormatter.string(from: Date())
}
