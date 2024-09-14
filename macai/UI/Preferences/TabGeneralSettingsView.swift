//
//  TabGeneralSettingsView.swift
//  macai
//
//  Created by Renat Notfullin on 11.11.2023.
//

import SwiftUI

struct GeneralSettingsView: View {
    @State private var gptToken: String = ""
    @AppStorage("gptToken") var gptTokenFromAppStorage: String = ""
    @AppStorage("apiUrl") var apiUrl: String = AppConstants.apiUrlChatCompletions
    @AppStorage("chatContext") var chatContext: Double = AppConstants.chatGptContextSize
    @AppStorage("useChatGptForNames") var useChatGptForNames: Bool = false
    @AppStorage("useStream") var useStream: Bool = true
    @Binding var lampColor: Color
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack {
                HStack {
                    Text("LLM API Settings")
                        .font(.headline)

                    Spacer()
                }
                HStack {
                    Text("Note: These settings will be applied to all chats, including existing ones.")
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.bottom, 16)
                

                VStack {
                    HStack {
                        Text("ChatGPT/LLM API URL:")
                            .frame(width: 160, alignment: .leading)

                        TextField("Paste your URL here", text: $apiUrl)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button(action: {
                            apiUrl = AppConstants.apiUrlChatCompletions
                        }) {
                            Text("Reset to default")
                        }
                    }
                }

                HStack {
                    Text("ChatGPT API Token:")
                        .frame(width: 160, alignment: .leading)

                    TextField("Paste your token here", text: $gptToken)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($isFocused)
                        .blur(radius: !gptToken.isEmpty && !isFocused ? 3 : 0.0, opaque: false)
                        .onChange(of: gptToken) { newValue in
                            do {
                                try TokenManager.setToken(newValue, for: "chatgpt")
                            } catch {
                                print("Error setting token: \(error)")
                            }
                        }
                }
            }

            HStack {
                Spacer()
                Link(
                    "How to get API Token",
                    destination: URL(
                        string: "https://help.openai.com/en/articles/4936850-where-do-i-find-my-secret-api-key"
                    )!
                )
                .font(.subheadline)
                .foregroundColor(.blue)
            }

            HStack {
                Slider(
                    value: $chatContext,
                    in: 5...100,
                    step: 5
                ) {
                    Text("Context size")
                } minimumValueLabel: {
                    Text("5")
                } maximumValueLabel: {
                    Text("100")
                }

                Text(String(format: ("%.0f messages"), chatContext))
                    .frame(width: 90)
            }
            .padding(.top, 16)

            HStack {
                Spacer()
                ButtonTestApiTokenAndModel(lampColor: $lampColor)
            }
            .padding(.top, 16)

            VStack {
                    Toggle(isOn: $useChatGptForNames) {
                        HStack {
                            Text("Automatically generate chat names (using selected model)")
                            Button(action: {
                            }) {
                                Image(systemName: "questionmark.circle")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Chat name will be generated based on chat messages. Selected model will be used to generate chat name")

                            Spacer()
                        }
                    }
                    Toggle(isOn: $useStream) {
                        HStack {
                            Text("Use stream responses")
                            Button(action: {
                            }) {
                                Image(systemName: "questionmark.circle")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("If on, the ChatGPT response will be streamed to the client. This will allow you to see the response in real-time. If off, the response will be sent to the client only after the model has finished processing.")

                            Spacer()
                        }
                    }
                }
                .padding(.vertical, 8)

        }
        .padding(32)
        .onAppear {
            do {
                gptToken = try TokenManager.getToken(for: "chatgpt")!
            } catch {
                if gptTokenFromAppStorage != "" {
                    gptToken = gptTokenFromAppStorage
                    do {
                        print("Found token in app storage. Saving to keychain")
                        try TokenManager.setToken(gptToken, for: "chatgpt")
                        gptTokenFromAppStorage = ""
                    } catch {
                        print("Failed to set token: \(error.localizedDescription)")
                    }
                }
                print("Failed to get token: \(error.localizedDescription)")
            }
        }
    }
}
