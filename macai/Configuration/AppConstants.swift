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
    static let apiUrlOpenAIResponses: String = "https://api.openai.com/v1/responses"
    static let chatGptDefaultModel = "gpt-4o"
    static var defaultPrimaryModel: String {
        defaultApiConfigurations[defaultApiType]?.defaultModel ?? chatGptDefaultModel
    }

    static func defaultModel(for type: String?) -> String {
        guard let type = type?.lowercased() else {
            return defaultPrimaryModel
        }
        return defaultApiConfigurations[type]?.defaultModel ?? defaultPrimaryModel
    }

    static let chatGptContextSize: Double = 10
    static let chatGptSystemMessage: String = String(
        format:
            "You are Large Language Model. Answer as concisely as possible. Your answers should be informative, helpful and engaging.",
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
    static let defaultPersonaTemperature: Float = 1.0
    static let defaultTemperatureForChat: Float = 0.7
    static let geminiLegacyAPIURL = "https://generativelanguage.googleapis.com/v1beta/chat/completions"
    static let geminiCurrentAPIURL = "https://generativelanguage.googleapis.com/v1beta/models"
    static let geminiURLMigrationCompletedKey = "GeminiURLMigrationCompleted"
    static let geminiURLMigrationSkippedKey = "GeminiURLMigrationSkipped"
    static let geminiMigrationPendingNotificationKey = "GeminiURLMigrationPendingMessage"
    static let chatCompletionsMigrationCompletedKey = "ChatCompletionsMigrationCompleted"
    static let chatCompletionsMigrationPendingNotificationKey = "ChatCompletionsMigrationPendingMessage"
    static let personaOrderingPatchCompletedKey = "PersonaOrderingPatchCompleted"
    static let imageUploadsPatchCompletedKey = "ImageUploadsPatchCompleted"
    static let imageGenerationPatchCompletedKey = "ImageGenerationPatchCompleted"
    static let apiServiceMigrationCompletedKey = "APIServiceMigrationCompleted"
    static let entityIDBackfillCompletedKey = "EntityIDBackfillCompleted"
    static let messageSequenceBackfillCompletedKey = "MessageSequenceBackfillCompleted"
    static let openAiReasoningModels: [String] = [
        "o1", "o1-preview", "o1-mini", "o3-mini", "o3-mini-high", "o3-mini-2025-01-31", "o1-preview-2024-09-12",
        "o1-mini-2024-09-12", "o1-2024-12-17",
    ]
    static let firaCode = "FiraCodeRoman-Regular"
    static let ptMono = "PTMono-Regular"
    static let cloudKitContainerIdentifier: String? = {
        let value = Bundle.main.object(forInfoDictionaryKey: "CloudKitContainerIdentifier") as? String
        return value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? value : nil
    }()

    struct Persona {
        let name: String
        let color: String
        let message: String
        let temperature: Float
    }

    struct PersonaPresets {
        static let defaultAssistant = Persona(
            name: "Default Assistant",
            color: "#FF4444",
            message:
                "You are Large Language Model. Answer as concisely as possible. Your answers should be informative, helpful and engaging.",
            temperature: 0.7
        )

        static let softwareEngineer = Persona(
            name: "Software Engineer",
            color: "#FF8800",
            message: """
                You are an experienced software engineer with deep knowledge of computer science fundamentals, software design patterns, and modern development practices. 
                When the answer involves the review of the existing code: 
                Before writing or suggesting code, you conduct a deep-dive review of the existing code and describe how it works between <CODE_REVIEW> tags. Once you have completed the review, you produce a careful plan for the change in <PLANNING> tags. Pay attention to variable names and string literals - when reproducing code make sure that these do not change unless necessary or directed. If naming something by convention surround in double colons and in ::UPPERCASE::.
                Finally, you produce correct outputs that provide the right balance between solving the immediate problem and remaining generic and flexible.
                You always ask for clarifications if anything is unclear or ambiguous. You stop to discuss trade-offs and implementation options if there are choices to make.
                It is important that you follow this approach, and do your best to teach your interlocutor about making effective decisions. You avoid apologising unnecessarily, and review the conversation to never repeat earlier mistakes.
                """,
            temperature: 0.3
        )

        static let aiExpert = Persona(
            name: "AI Expert",
            color: "#FFCC00",
            message:
                "You are an AI expert with deep knowledge of artificial intelligence, machine learning, and natural language processing. Provide insights into the current state of AI science, explain complex AI concepts in simple terms, and offer guidance on creating effective prompts for various AI models. Stay updated on the latest AI research, ethical considerations, and practical applications of AI in different industries. Help users understand the capabilities and limitations of AI systems, and provide advice on integrating AI technologies into various projects or workflows.",
            temperature: 0.8
        )

        static let scienceExpert = Persona(
            name: "Natural Sciences Expert",
            color: "#33CC33",
            message: """
                You are an expert in natural sciences with comprehensive knowledge of physics, chemistry, biology, and related fields. 
                Provide clear explanations of:
                - Scientific concepts and theories
                - Natural phenomena and their underlying mechanisms
                - Latest scientific discoveries and research
                - Mathematical models and scientific methods
                - Laboratory procedures and experimental design
                Use precise scientific terminology while making complex concepts accessible. Include relevant equations and diagrams when helpful, and always emphasize the empirical evidence supporting scientific claims.
                """,
            temperature: 0.2
        )

        static let historyBuff = Persona(
            name: "History Buff",
            color: "#3399FF",
            message:
                "You are a passionate and knowledgeable historian. Provide accurate historical information, analyze historical events and their impacts, and draw connections between past and present. Offer multiple perspectives on historical events, cite sources when appropriate, and engage users with interesting historical anecdotes and lesser-known facts.",
            temperature: 0.2
        )

        static let fitnessTrainer = Persona(
            name: "Fitness Trainer",
            color: "#6633FF",
            message:
                "You are a certified fitness trainer with expertise in various exercise modalities and nutrition. Provide safe, effective workout routines, offer nutritional advice, and help users set realistic fitness goals. Explain the science behind fitness concepts, offer modifications for different fitness levels, and emphasize the importance of consistency and proper form.",
            temperature: 0.5
        )

        static let dietologist = Persona(
            name: "Dietologist",
            color: "#CC33FF",
            message:
                "You are a certified nutritionist and dietary expert with extensive knowledge of various diets, nutritional science, and food-related health issues. Provide evidence-based advice on balanced nutrition, explain the pros and cons of different diets (such as keto, vegan, paleo, etc.), and offer meal planning suggestions. Help users understand the nutritional content of foods, suggest healthy alternatives, and address specific dietary needs related to health conditions or fitness goals. Always emphasize the importance of consulting with a healthcare professional for personalized medical advice.",
            temperature: 0.2
        )

        static let dbtPsychologist = Persona(
            name: "DBT Psychologist",
            color: "#FF3399",
            message:
                "You are a psychologist specializing in Dialectical Behavior Therapy (DBT). Provide guidance on DBT techniques, mindfulness practices, and strategies for emotional regulation. Offer support for individuals dealing with borderline personality disorder, depression, anxiety, and other mental health challenges. Explain DBT concepts, such as distress tolerance and interpersonal effectiveness, in an accessible manner. Emphasize the importance of professional mental health support and never attempt to diagnose or replace real therapy. Instead, offer general coping strategies and information about DBT principles.",
            temperature: 0.7
        )

        static let allPersonas: [Persona] = [
            defaultAssistant, softwareEngineer, aiExpert, scienceExpert,
            historyBuff, fitnessTrainer, dietologist, dbtPsychologist,
        ]
    }

    static let defaultApiType = "openai-responses"

    struct defaultApiConfiguration {
        let name: String
        let url: String
        let apiKeyRef: String
        let apiModelRef: String
        let defaultModel: String
        let models: [String]
        var maxTokens: Int? = nil
        var inherits: String? = nil
        var modelsFetching: Bool = true
        var imageUploadsSupported: Bool = false
        var imageGenerationSupported: Bool = false
        var autoEnableImageGenerationModels: [String] = []
    }

    static let defaultApiConfigurations = [
        "openai-responses": defaultApiConfiguration(
            name: "OpenAI",
            url: Self.apiUrlOpenAIResponses,
            apiKeyRef: "https://platform.openai.com/docs/api-reference/api-keys",
            apiModelRef: "https://platform.openai.com/docs/models",
            defaultModel: "gpt-5",
            models: [
                "gpt-5"
            ],
            imageUploadsSupported: true,
            imageGenerationSupported: true
        ),
        "chatgpt": defaultApiConfiguration(
            name: "Generic Completions API",
            url: Self.apiUrlChatCompletions,
            apiKeyRef: "https://platform.openai.com/docs/api-reference/api-keys",
            apiModelRef: "https://platform.openai.com/docs/models",
            defaultModel: "gpt-4o",
            models: [
                "gpt-5"
            ],
            imageUploadsSupported: true
        ),
        "ollama": defaultApiConfiguration(
            name: "Ollama",
            url: "http://localhost:11434/api/chat",
            apiKeyRef: "",
            apiModelRef: "https://ollama.com/library",
            defaultModel: "llama3.1",
            models: [
                "llama3.3",
                "llama3.2",
                "llama3.1",
                "llama3.1:70b",
                "llama3.1:400b",
                "qwen2.5:3b",
                "qwen2.5",
                "qwen2.5:14b",
                "qwen2.5:32b",
                "qwen2.5:72b",
                "qwen2.5-coder",
                "phi3",
                "gemma",
            ]
        ),
        "claude": defaultApiConfiguration(
            name: "Claude",
            url: "https://api.anthropic.com/v1/messages",
            apiKeyRef: "https://docs.anthropic.com/en/docs/initial-setup#prerequisites",
            apiModelRef: "https://docs.anthropic.com/en/docs/about-claude/models",
            defaultModel: "claude-4.1-sonnet",
            models: [
                "claude-4.1-sonnet",
                "claude-4.1-opus",
                "claude-3-5-sonnet-latest",
                "claude-3-opus-latest",
                "claude-3-haiku-20240307",
            ],
            maxTokens: 4096
        ),
        "xai": defaultApiConfiguration(
            name: "xAI",
            url: "https://api.x.ai/v1/chat/completions",
            apiKeyRef: "https://console.x.ai/",
            apiModelRef: "https://docs.x.ai/docs#models",
            defaultModel: "grok-4",
            models: [
                "grok-4",
                "grok-beta",
            ],
            inherits: "chatgpt"
        ),
        "gemini": defaultApiConfiguration(
            name: "Google Gemini",
            url: "https://generativelanguage.googleapis.com/v1beta/models",
            apiKeyRef: "https://aistudio.google.com/app/apikey",
            apiModelRef: "https://ai.google.dev/gemini-api/docs/models/gemini#model-variations",
            defaultModel: "gemini-2.5-pro",
            models: [
                "gemini-2.5-pro",
                "gemini-2.5-flash",
                "gemini-2.5-flash-image-preview",
                "gemini-2.0-flash-exp",
                "gemini-1.5-pro",
                "gemini-1.5-flash",
                "gemini-1.5-flash-8b",
            ],
            imageUploadsSupported: true,
            imageGenerationSupported: true,
            autoEnableImageGenerationModels: ["gemini-2.5-flash-image-preview"]
        ),
        "perplexity": defaultApiConfiguration(
            name: "Perplexity",
            url: "https://api.perplexity.ai/chat/completions",
            apiKeyRef: "https://www.perplexity.ai/settings/api",
            apiModelRef: "https://docs.perplexity.ai/guides/model-cards#supported-models",
            defaultModel: "llama-3.1-sonar-large-128k-online",
            models: [
                "sonar-reasoning-pro",
                "sonar-reasoning",
                "sonar-pro",
                "sonar",
                "llama-3.1-sonar-small-128k-online",
                "llama-3.1-sonar-large-128k-online",
                "llama-3.1-sonar-huge-128k-online",
            ],
            modelsFetching: false
        ),
        "deepseek": defaultApiConfiguration(
            name: "DeepSeek",
            url: "https://api.deepseek.com/chat/completions",
            apiKeyRef: "https://api-docs.deepseek.com/",
            apiModelRef: "https://api-docs.deepseek.com/quick_start/pricing",
            defaultModel: "deepseek-chat",
            models: [
                "deepseek-chat",
                "deepseek-reasoner",
            ]
        ),
        "openrouter": defaultApiConfiguration(
            name: "OpenRouter",
            url: "https://openrouter.ai/api/v1/chat/completions",
            apiKeyRef: "https://openrouter.ai/docs/api-reference/authentication#using-an-api-key",
            apiModelRef: "https://openrouter.ai/docs/overview/models",
            defaultModel: "deepseek/deepseek-r1:free",
            models: [
                "openai/gpt-4o",
                "deepseek/deepseek-r1:free",
            ]
        ),
        "vertex": defaultApiConfiguration(
            name: "Google Vertex AI",
            url: "https://us-central1-aiplatform.googleapis.com/v1",
            apiKeyRef: "",
            apiModelRef: "https://cloud.google.com/vertex-ai/generative-ai/docs/learn/models",
            defaultModel: "gemini-2.5-pro",
            models: [
                "gemini-2.5-pro",
                "gemini-2.5-flash",
                "gemini-2.0-flash",
                "gemini-1.5-pro",
                "gemini-1.5-flash",
                "claude-sonnet-4-5@20250929",
                "claude-3-5-sonnet-v2@20241022",
                "claude-3-opus@20240229",
                "claude-3-haiku@20240307",
            ],
            modelsFetching: false,
            imageUploadsSupported: true,
            imageGenerationSupported: true,
            autoEnableImageGenerationModels: ["gemini-2.0-flash-image-generation"]
        ),
    ]

    static let apiTypes = [
        "openai-responses", "chatgpt", "ollama", "claude", "xai", "gemini", "perplexity", "deepseek", "openrouter",
        "vertex",
    ]

    static let defaultGcpRegion = "us-central1"
    static let newChatNotification = Notification.Name("newChatNotification")
    static let largeMessageSymbolsThreshold = 25000
    static let thumbnailSize: CGFloat = 300
    static let maxHighlightableTextLength = 100000
    static let searchDebounceTime: TimeInterval = 0.3
    
    static let defaultHighlightColor = "#FFFF00"
    static let currentHighlightColor = "#FFA500"
}

func getCurrentFormattedDate() -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    return dateFormatter.string(from: Date())
}
