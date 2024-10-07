//
//  ButtonTestApiTokenAndModel.swift
//  macai
//
//  Created by Renat Notfullin on 12.11.2023.
//

import SwiftUI

struct ButtonTestApiTokenAndModel: View {
    @Binding var lampColor: Color
    var gptToken: String = ""
    var gptModel: String = AppConstants.chatGptDefaultModel
    var apiUrl: String = AppConstants.apiUrlChatCompletions
    var apiType: String = "chatgpt"
    
    @Environment(\.managedObjectContext) private var viewContext
        
        var body: some View {
            Button(action: {
                testAPI()
            }) {
                Text("Test API token & model")
                Circle()
                    .fill(lampColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: lampColor, radius: 4, x: 0, y: 0)
                    .padding(.leading, 6)
                    .padding(.top, 2)
            }
        }
        
        private func testAPI() {
            lampColor = .yellow
            
            let config = APIServiceConfig(
                name: apiType,
                apiUrl: URL(string: apiUrl)!,
                apiKey: gptToken,
                model: gptModel
            )
            
            let apiService = APIServiceFactory.createAPIService(config: config)
            lazy var messageManager: MessageManager = {
                return MessageManager(apiService: APIServiceFactory.createAPIService(config: config), viewContext: self.viewContext)
            }()
            
            // Create a temporary chat for testing
            let testChat = ChatEntity(context: viewContext)
            testChat.systemMessage = "You are a test assistant."
            testChat.gptModel = gptModel
            
            messageManager.testAPI() { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(_):
                        lampColor = .green
                    case .failure(let error):
                        lampColor = .red
                        showErrorAlert(error: error as! APIError)
                    }
                    
                    // Clean up the temporary chat
                    viewContext.delete(testChat)
                    try? viewContext.save()
                }
            }
        }
        
        private func showErrorAlert(error: APIError) {
            let alert = NSAlert()
            alert.messageText = "API Connection Test Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
