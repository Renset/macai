//
//  PreferencesView.swift
//  macai
//
//  Created by Renat Notfullin on 11.03.2023.
//

import Foundation
import SwiftUI

struct APIRequestData: Codable {
    let model: String
    let messages = [
        [
            "role": "system",
            "content": "You are ChatGPT, a large language model trained by OpenAI. Say hi, if you're there",
        ]
    ]

}

func testAPIToken(model: String, token: String, completion: @escaping (Result<Bool, Error>) -> Void) {
    let url = URL(string: "https://api.openai.com/v1/chat/completions")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    let requestData = APIRequestData(model: model)
    do {
        let jsonData = try JSONEncoder().encode(requestData)
        request.httpBody = jsonData
    }
    catch {
        completion(.failure(error))
        return
    }

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        //        if let responseString = String(data: data ?? Data(), encoding: .utf8) {
        //            print("Response: \(responseString)")
        //        }

        if let error = error {
            print("Error: \(error)")
            completion(.failure(error))
            return
        }

        guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode)
        else {
            completion(
                .failure(NSError(domain: "", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
            )
            return
        }

        // Add any additional response handling logic here
        // For this example, we'll just return true for a successful response
        completion(.success(true))
    }
    task.resume()
}

struct PreferencesView: View {
    @AppStorage("gptToken") var gptToken: String = ""
    @AppStorage("gptModel") var gptModel: String = AppConstants.chatGptDefaultModel
    @AppStorage("systemMessage") var systemMessage = AppConstants.chatGptSystemMessage
    @AppStorage("chatContext") var chatContext: Double = AppConstants.chatGptContextSize
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)
    @State private var lampColor: Color = .gray
    @State private var previousGptModel: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {

                VStack {
                    // ChatGPT settings section

                    HStack {
                        Text("ChatGPT Global Settings")
                            .font(.headline)

                        Spacer()
                    }

                    HStack {
                        Text("ChatGPT API Token:")
                            .frame(width: 160, alignment: .leading)

                        TextField("Paste your token here", text: $gptToken)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                    }

                }

                // display link to get token at the right side
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

            }
            .padding(.bottom)

            Spacer()

            VStack {
                HStack {
                    Text("New chat settings")
                        .font(.headline)
                    Spacer()
                }

                HStack {
                    // Select model
                    Text("ChatGPT Model:")
                        .frame(width: 160, alignment: .leading)

                    Picker("", selection: $gptModel) {
                        Text("gpt-3.5-turbo").tag("gpt-3.5-turbo")
                        Text("gpt-3.5-turbo-0301").tag("gpt-3.5-turbo-0301")
                        Text("gpt-4").tag("gpt-4")
                        Text("gpt-4-0314").tag("gpt-4-0314")
                        Text("gpt-4-32k").tag("gpt-4-32k")
                        Text("gpt-4-32k-0314").tag("gpt-4-32k-0314")
                    }.onReceive([self.gptModel].publisher.first()) { newValue in
                        if self.gptModel != self.previousGptModel {
                            self.lampColor = .gray
                            self.previousGptModel = self.gptModel
                        }
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

                // Test API token
                HStack {
                    Spacer()
                    Button(action: {
                        lampColor = .yellow
                        testAPIToken(model: gptModel, token: gptToken) { result in
                            DispatchQueue.main.async {
                                switch result {
                                case .success(_):
                                    lampColor = .green
                                case .failure(_):
                                    lampColor = .red
                                }
                            }
                        }
                    }) {
                        Text("Test model and API token")
                        Circle()
                            .fill(lampColor)
                            .frame(width: 8, height: 8)
                            .shadow(color: lampColor, radius: 4, x: 0, y: 0)
                            .padding(.leading, 6)
                            .padding(.top, 2)
                    }

                }
                .padding(.top, 16)

                Spacer()

                VStack {

                    Spacer()

                    // Backup & Restore section
                    HStack {
                        Text("Backup & Restore")
                            .font(.headline)
                        Spacer()
                    }

                    // Export chats
                    HStack {
                        Text("Export chats history")
                        Spacer()
                        Button("Export to file...") {

                            store.loadFromCoreData { result in

                                switch result {

                                case .failure(let error):
                                    fatalError(error.localizedDescription)

                                case .success(let chats):
                                    let encoder = JSONEncoder()
                                    encoder.outputFormatting = .prettyPrinted
                                    let data = try! encoder.encode(chats)
                                    // save to user defined location
                                    let savePanel = NSSavePanel()
                                    savePanel.allowedContentTypes = [.json]
                                    savePanel.nameFieldStringValue = "chats.json"
                                    savePanel.begin { (result) in
                                        if result == .OK {
                                            do {
                                                try data.write(to: savePanel.url!)
                                            }
                                            catch {
                                                print(error)
                                            }
                                        }
                                    }

                                }

                            }

                        }
                    }

                    //                // Import chats
                    HStack {
                        Text("Import chats history")
                        Spacer()
                        Button("Import from file...") {
                            let openPanel = NSOpenPanel()
                            openPanel.allowedContentTypes = [.json]
                            openPanel.begin { (result) in
                                if result == .OK {
                                    do {
                                        let data = try Data(contentsOf: openPanel.url!)
                                        let decoder = JSONDecoder()
                                        let chats = try decoder.decode([Chat].self, from: data)

                                        store.saveToCoreData(chats: chats) { result in
                                            print("State saved")
                                            if case .failure(let error) = result {
                                                fatalError(error.localizedDescription)
                                            }
                                        }

                                    }
                                    catch {
                                        print(error)
                                    }
                                }
                            }
                        }
                    }

                    HStack {
                        Text("More options for ChatGPT API settings are coming soon, stay tuned!")
                            .font(.system(size: 8))
                    }
                    .padding(.top, 20)
                }
            }

        }
        .padding(16)
        .frame(width: 420, height: 580)
        .onAppear(perform: {
            store.saveInCoreData()
        })
    }

}
