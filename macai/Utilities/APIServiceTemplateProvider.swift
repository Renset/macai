//
//  APIServiceTemplateProvider.swift
//  macai
//
//  Created by Renat Notfullin on 19.09.2025
//

import Foundation

enum APIServiceTemplateProvider {
    private static let resourceName = "APIServiceTemplates"

    static func loadCatalog() -> APIServiceTemplateCatalog {
        let decoder = JSONDecoder()
        for bundle in candidateBundles {
            if let url = bundle.url(forResource: resourceName, withExtension: "json") {
                do {
                    let data = try Data(contentsOf: url)
                    return try decoder.decode(APIServiceTemplateCatalog.self, from: data)
                }
                catch {
                    NSLog("[APIServiceTemplateProvider] Failed to decode templates: \(error.localizedDescription)")
                }
            }
        }

        NSLog("[APIServiceTemplateProvider] Falling back to bundled defaults")
        return fallbackCatalog
    }

    private static var candidateBundles: [Bundle] {
        var bundles: [Bundle] = [Bundle.main]
        bundles.append(Bundle(for: BundleToken.self))
        #if SWIFT_PACKAGE
        bundles.append(Bundle.module)
        #endif
        return bundles
    }

    private static var fallbackCatalog: APIServiceTemplateCatalog {
        guard let data = fallbackJSON.data(using: .utf8) else { return .empty }
        do {
            return try JSONDecoder().decode(APIServiceTemplateCatalog.self, from: data)
        }
        catch {
            NSLog("[APIServiceTemplateProvider] Failed to decode fallback templates: \(error.localizedDescription)")
            return .empty
        }
    }

    private static let fallbackJSON = """
    {
        "providers": [
            {
                "id": "openai-responses",
                "displayName": "OpenAI",
                "defaultName": "OpenAI GPT-4.1",
                "note": "Requires an API key from platform.openai.com",
                "models": [
                    {
                        "id": "gpt-5",
                        "displayName": "GPT-5",
                        "isDefault": true,
                        "settings": {
                            "generateChatNames": true,
                            "contextSize": 30,
                            "useStreaming": true,
                            "allowImageUploads": true,
                            "imageGenerationSupported": true
                        }
                    }
                ]
            },
            {
                "id": "chatgpt",
                "displayName": "Generic Completions API",
                "defaultName": "OpenAI GPT-5",
                "note": "Requires an API key from platform.openai.com",
                "models": [
                    {
                        "id": "gpt-5",
                        "displayName": "GPT-5",
                        "isDefault": true,
                        "settings": {
                            "generateChatNames": true,
                            "contextSize": 30,
                            "useStreaming": true,
                            "allowImageUploads": true,
                            "imageGenerationSupported": false
                        }
                    }
                ]
            },
            {
                "id": "claude",
                "displayName": "Claude",
                "defaultName": "Claude Sonnet 4",
                "note": "Anthropic keys start with `sk-ant-`.",
                "models": [
                    {
                        "id": "claude-4.1-sonnet",
                        "displayName": "Sonnet 4",
                        "isDefault": true,
                        "settings": {
                            "generateChatNames": true,
                            "contextSize": 40,
                            "useStreaming": true,
                            "allowImageUploads": true,
                            "imageGenerationSupported": false
                        }
                    },
                    {
                        "id": "claude-4.1-opus",
                        "displayName": "Opus 4.1",
                        "settings": {
                            "generateChatNames": true,
                            "contextSize": 40,
                            "useStreaming": true,
                            "allowImageUploads": true,
                            "imageGenerationSupported": false
                        }
                    }
                ]
            },
            {
                "id": "gemini",
                "displayName": "Gemini",
                "defaultName": "Gemini 2.5 Pro",
                "note": "Gemini uses Google AI Studio keys.",
                "models": [
                    {
                        "id": "gemini-2.5-pro",
                        "displayName": "2.5 Pro",
                        "isDefault": true,
                        "settings": {
                            "generateChatNames": true,
                            "contextSize": 32,
                            "useStreaming": true,
                            "allowImageUploads": true,
                            "imageGenerationSupported": false
                        }
                    },
                    {
                        "id": "gemini-2.5-flash",
                        "displayName": "2.5 Flash",
                        "settings": {
                            "generateChatNames": true,
                            "contextSize": 32,
                            "useStreaming": true,
                            "allowImageUploads": true,
                            "imageGenerationSupported": false
                        }
                    },
                    {
                        "id": "gemini-2.5-flash-image-preview",
                        "displayName": "Nano Banana (2.5 Flash Image Preview)",
                        "description": "Enables image preview capabilities",
                        "note": "Auto-enables image generation inside chats.",
                        "settings": {
                            "generateChatNames": true,
                            "contextSize": 32,
                            "useStreaming": true,
                            "allowImageUploads": true,
                            "imageGenerationSupported": true
                        }
                    }
                ]
            },
            {
                "id": "xai",
                "displayName": "xAI",
                "defaultName": "xAI Grok 4",
                "note": "Use the key from console.x.ai",
                "models": [
                    {
                        "id": "grok-4",
                        "displayName": "Grok 4",
                        "isDefault": true,
                        "settings": {
                            "generateChatNames": true,
                            "contextSize": 32,
                            "useStreaming": true,
                            "allowImageUploads": false,
                            "imageGenerationSupported": false
                        }
                    },
                    {
                        "id": "custom",
                        "displayName": "Custom",
                        "requiresExpertMode": true,
                        "description": "Switches to Expert mode so you can configure any Grok variant or custom endpoint."
                    }
                ]
            }
        ]
    }
    """

    private final class BundleToken {}
}
