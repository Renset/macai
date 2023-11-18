//
//  TabGeneralSettingsView.swift
//  macai
//
//  Created by Renat Notfullin on 11.11.2023.
//

import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage("gptToken") var gptToken: String = ""
    @AppStorage("apiUrl") var apiUrl: String = AppConstants.apiUrlChatCompletions
    @AppStorage("chatContext") var chatContext: Double = AppConstants.chatGptContextSize
    @AppStorage("useChatGptForNames") var useChatGptForNames: Bool = false
    @Binding var lampColor: Color
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack {
                HStack {
                    Text("ChatGPT API Settings")
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
                        Text("ChatGPT API URL:")
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
                            Text("Automatically generate chat names")
                            Button(action: {
                            }) {
                                Image(systemName: "questionmark.circle")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Chat name will be generated based on chat messages. To reduce API costs, model chat-gpt-3.5-turbo will be used for this purpose.")

                            Spacer()
                        }
                    }
                }
                .padding(.vertical, 8)

        }
        .padding(32)
    }
}
