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
    var gptModel: String = AppConstants.defaultPrimaryModel
    var apiUrl: String = AppConstants.apiUrlOpenAIResponses
    var apiType: String = AppConstants.defaultApiType
    var imageGenerationSupported: Bool = false
    @State var testOk: Bool = false

    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        ButtonWithStatusIndicator(
            title: "Test API token & model",
            action: { testAPI() },
            isLoading: lampColor == .yellow,
            hasError: lampColor == .red,
            errorMessage: nil,
            successMessage: "API connection test successful",
            isSuccess: testOk
        )
    }

    private func testAPI() {
        lampColor = .yellow
        self.testOk = false

        let config = APIServiceConfig(
            name: apiType,
            apiUrl: URL(string: apiUrl)!,
            apiKey: gptToken,
            model: gptModel
        )
        let apiService = APIServiceFactory.createAPIService(
            config: config,
            imageGenerationSupported: imageGenerationSupported
        )
        let messageManager = MessageManager(apiService: apiService, viewContext: viewContext)
        messageManager.testAPI(model: gptModel) { result in
            DispatchQueue.main.async {
                switch result {

                case .success(_):
                    lampColor = .green
                    self.testOk = true

                case .failure(let error):
                    lampColor = .red
                    let errorMessage =
                        switch error as! APIError {
                        case .requestFailed(let error): error.localizedDescription
                        case .invalidResponse: "Response is invalid"
                        case .decodingFailed(let message): message
                        case .unauthorized: "Unauthorized"
                        case .rateLimited: "Rate limited"
                        case .serverError(let message): message
                        case .unknown(let message): message
                        case .noApiService(let message): message
                        case .attachmentNotReady(let message): message
                        }
                    showErrorAlert(error: errorMessage)
                }
            }
        }
    }

    private func showErrorAlert(error: String) {
        let alert = NSAlert()
        alert.messageText = "API Connection Test Failed"
        alert.informativeText = error
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
