//
//  ButtonTestApiTokenAndModel.swift
//  macai
//
//  Created by Renat Notfullin on 12.11.2023.
//

import SwiftUI

struct ButtonTestAPIConnection: View {
    @Binding var lampColor: Color
    var apiKey: String = ""
    var apiUrl: String = AppConstants.apiUrlOpenAIResponses
    var apiType: String = AppConstants.defaultApiType
    var customHeaders: [String: String] = [:]
    @State private var testOk = false
    @State private var hasWarning = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        ButtonWithStatusIndicator(
            title: "Test connection",
            action: testAPI,
            isLoading: lampColor == .yellow,
            hasError: lampColor == .red,
            errorMessage: errorMessage,
            successMessage: statusMessage ?? "API connection test successful",
            isSuccess: testOk,
            isWarning: hasWarning
        )
    }

    private func testAPI() {
        guard let url = URL(string: apiUrl) else {
            lampColor = .red
            showErrorAlert(error: "The API URL is invalid: \(apiUrl)")
            return
        }

        lampColor = .yellow
        testOk = false
        hasWarning = false
        statusMessage = nil
        errorMessage = nil

        let config = APIServiceConfig(
            name: apiType,
            apiUrl: url,
            apiKey: apiKey,
            model: "",
            customHeaders: customHeaders
        )
        let apiService = APIServiceFactory.createAPIService(config: config)

        Task { @MainActor in
            do {
                let result = try await apiService.testConnection()
                if result.authenticationVerified {
                    lampColor = .green
                    testOk = true
                    statusMessage = "Connection successful"
                } else {
                    lampColor = .orange
                    hasWarning = true
                    statusMessage = "Endpoint reachable · token not verified"
                }
            } catch {
                lampColor = .red
                errorMessage = Self.message(for: error)
                showErrorAlert(error: errorMessage ?? "Unknown error")
            }
        }
    }

    private static func message(for error: Error) -> String {
        switch error as? APIError {
        case .requestFailed(let nestedError): message(for: nestedError)
        case .invalidResponse: "Response is invalid"
        case .decodingFailed(let message): message
        case .unauthorized: "Unauthorized. Check the API key."
        case .rateLimited: "Rate limited"
        case .serverError(let message): message
        case .unknown(let message): message
        case .noApiService(let message): message
        case .attachmentNotReady(let message): message
        case nil: error.localizedDescription
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
