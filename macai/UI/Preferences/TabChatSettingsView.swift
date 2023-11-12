//
//  TabChatSettingsView.swift
//  macai
//
//  Created by Renat Notfullin on 11.11.2023.
//

import SwiftUI

struct ChatSettingsView: View {
    @Binding var lampColor: Color
    @State private var previousGptModel: String = ""
    @State private var selectedGptModel: String = ""
    @AppStorage("gptToken") var gptToken: String = ""
    @AppStorage("gptModel") var gptModel: String = AppConstants.chatGptDefaultModel
    @AppStorage("systemMessage") var systemMessage = AppConstants.chatGptSystemMessage
    @AppStorage("chatContext") var chatContext: Double = AppConstants.chatGptContextSize
    @AppStorage("isCustomGptModel") var isCustomGptModel: Bool = false
    @AppStorage("apiUrl") var apiUrl: String = AppConstants.apiUrlChatCompletions
    

    var body: some View {
        VStack {
                HStack {
                    Text("New chat settings")
                        .font(.headline)
                    Spacer()
                }
            
                HStack {
                    Text("These settings will be applied to new chats only")
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.bottom, 16)

                HStack {
                    // Select model
                    Text("ChatGPT Model:")
                        .frame(width: 160, alignment: .leading)

                    Picker("", selection: $selectedGptModel) {
                        Text("gpt-3.5-turbo").tag("gpt-3.5-turbo")
                        Text("gpt-3.5-turbo-0301").tag("gpt-3.5-turbo-0301")
                        Text("gpt-4").tag("gpt-4")
                        Text("gpt-4-0314").tag("gpt-4-0314")
                        Text("gpt-4-32k").tag("gpt-4-32k")
                        Text("gpt-4-32k-0314").tag("gpt-4-32k-0314")
                        Text("gpt-4-1106-preview").tag("gpt-4-1106-preview")
                        Text("gpt-4-vision-preview").tag("gpt-4-vision-preview")
                        Text("Enter custom model").tag("custom")
                    }.onChange(of: selectedGptModel) { newValue in
                        if (newValue == "custom") {
                            isCustomGptModel = true
                        } else {
                            isCustomGptModel = false
                            gptModel = newValue
                        }

                        if self.gptModel != self.previousGptModel {
                            self.lampColor = .gray
                            self.previousGptModel = self.gptModel
                        }
                    }
                }

            if (self.isCustomGptModel) {
                    VStack {
                        TextField("Enter custom model name", text: $gptModel)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }

                HStack {
                    Spacer()
                    Link(
                        "Models reference",
                        destination: URL(string: "https://platform.openai.com/docs/models/overview")!
                    )
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }
                .padding(.bottom)

                VStack {
                    HStack {
                        Text("ChatGPT system message:")
                            .frame(alignment: .leading)
                        Spacer()
                    }

                    MessageInputView(
                        text: $systemMessage,
                        onEnter: {

                        }
                    )

                    HStack {
                        Spacer()
                        Button(action: {
                            systemMessage = AppConstants.chatGptSystemMessage
                        }) {
                            Text("Reset to default")
                        }
                    }

                }

            HStack {
                Spacer()
                ButtonTestApiTokenAndModel(lampColor: $lampColor)
            }
            .padding(.top, 16)
        }
        .padding(32)
        .onAppear(perform: {
            if (self.isCustomGptModel) {
                self.selectedGptModel = "custom"
            } else {
                self.selectedGptModel = self.gptModel
            }
        })
    }
}
