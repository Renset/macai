//
//  ButtonTestApiTokenAndModel.swift
//  macai
//
//  Created by Renat Notfullin on 12.11.2023.
//

import SwiftUI

struct ButtonTestApiTokenAndModel: View {
    @Binding var lampColor: Color
    @AppStorage("gptToken") var gptToken: String = ""
    @AppStorage("gptModel") var gptModel: String = AppConstants.chatGptDefaultModel
    @AppStorage("apiUrl") var apiUrl: String = AppConstants.apiUrlChatCompletions
    
    var body: some View {
        Button(action: {
            lampColor = .yellow
            testAPIToken(apiUrl: apiUrl, model: gptModel, token: gptToken) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(_):
                        lampColor = .green
                    case .failure(let error):
                        lampColor = .red
                        let alert = NSAlert()
                        alert.messageText = "API token test failed"
                        alert.informativeText = error.localizedDescription
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            }
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
}

struct APIErrorResponse: Decodable {
    let error: APIError
}

struct APIError: Decodable {
    let message: String
    let type: String?
    let param: String?
    let code: String?
}

func testAPIToken(apiUrl: String, model: String, token: String, completion: @escaping (Result<Bool, Error>) -> Void) {
    let url = URL(string: apiUrl)!
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
        if let error = error {
            print("Error: \(error)")
            completion(.failure(error))
            return
        }

        guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode)
        else {
            let errorDescription: String
            if let data = data,
               let responseText = String(data: data, encoding: .utf8) {
                do {
                    let errorResponse = try JSONDecoder().decode(APIErrorResponse.self, from: data)
                    errorDescription = errorResponse.error.message
                } catch {
                    print("JSON Decoding Error: \(error.localizedDescription)")
                    errorDescription = responseText
                }
            } else {
                errorDescription = "Invalid response"
            }
            let error = NSError(domain: "", code: 1001, userInfo: [NSLocalizedDescriptionKey: errorDescription])
            completion(.failure(error))
            return
        }
        completion(.success(true))
    }
    task.resume()
}
