//
//  APIServiceDetailView.swift
//  macai
//
//  Created by Renat Notfullin on 13.09.2024.
//

import SwiftUI

struct APIServiceDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.presentationMode) var presentationMode
    
    let apiService: APIServiceEntity?
    
    @State var name: String = ""
    @State var type: String = "ChatGPT"
    @State var url: String = ""
    @State var model: String = ""
    @State var contextSize: Float = 10
    @State var useStreamResponse: Bool = true
    @State var generateChatNames: Bool = false
    @State var defaultAiPersona: PersonaEntity? = nil
    @State private var apiKey: String = ""
    @State private var isCustomModel: Bool = false
    @State private var selectedModel: String = ""
    @State private var previousModel: String = ""
    @State private var lampColor: Color = .gray
    @State private var showingDeleteConfirmation: Bool = false
    @FocusState private var isFocused: Bool
    
    
    private let types = ["ChatGPT", "Ollama"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack {
                HStack {
                    Text("LLM API Settings")
                        .font(.headline)

                    Spacer()
                }
                VStack {
                    HStack {
                        Picker("API Type", selection: $type) {
                            ForEach(types, id: \.self) {
                                Text($0)
                            }
                        }

                    }
                }
                .padding(.bottom, 8)
                
                VStack {
                    HStack {
                        Text("API URL:")
                            .frame(width: 100, alignment: .leading)

                        TextField("Paste your URL here", text: $url)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button(action: {
                            url = AppConstants.apiUrlChatCompletions
                        }) {
                            Text("Default")
                        }
                    }
                }

                HStack {
                    Text("API Token:")
                        .frame(width: 100, alignment: .leading)

                    TextField("Paste your token here", text: $apiKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($isFocused)
                        .blur(radius: !apiKey.isEmpty && !isFocused ? 3 : 0.0, opaque: false)
                        .onChange(of: apiKey) { newValue in
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
                    value: $contextSize,
                    in: 5...100,
                    step: 5
                ) {
                    Text("Context size")
                } minimumValueLabel: {
                    Text("5")
                } maximumValueLabel: {
                    Text("100")
                }

                Text(String(format: ("%.0f messages"), contextSize))
                    .frame(width: 90)
            }
            .padding(.top, 16)

            VStack {
                    Toggle(isOn: $generateChatNames) {
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
                    Toggle(isOn: $useStreamResponse) {
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
            
            
            HStack {
                // Select model
                Text("LLM Model:")
                    .frame(width: 160, alignment: .leading)

                Picker("", selection: $selectedModel) {
                    Text("gpt-3.5-turbo").tag("gpt-3.5-turbo")
                    Text("gpt-3.5-turbo-0301").tag("gpt-3.5-turbo-0301")
                    Text("gpt-4-turbo").tag("gpt-4-turbo")
                    Text("gpt-4").tag("gpt-4")
                    Text("gpt-4o").tag("gpt-4o")
                    Text("gpt-4o-mini").tag("gpt-4o-mini")
                    Text("gpt-4-0314").tag("gpt-4-0314")
                    Text("gpt-4-32k").tag("gpt-4-32k")
                    Text("gpt-4-32k-0314").tag("gpt-4-32k-0314")
                    Text("gpt-4-1106-preview").tag("gpt-4-1106-preview")
                    Text("gpt-4-vision-preview").tag("gpt-4-vision-preview")
                    Text("llama3").tag("llama3")
                    Text("llama3.1").tag("llama3.1")
                    Text("Enter custom model").tag("custom")
                }.onChange(of: selectedModel) { newValue in
                    if (newValue == "custom") {
                        isCustomModel = true
                    } else {
                        isCustomModel = false
                        model = newValue
                    }

                    if self.model != self.previousModel {
                        self.lampColor = .gray
                        self.previousModel = self.model
                    }
                }
            }

        if (self.isCustomModel) {
                VStack {
                    TextField("Enter custom model name", text: $model)
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
            
            HStack {
                if apiService != nil {
                    Button(action: {
                        showingDeleteConfirmation = true
                    }) {
                        Label("Delete", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                }
                Spacer()
                ButtonTestApiTokenAndModel(lampColor: $lampColor, gptToken: apiKey, gptModel: model, apiUrl: url)
                Button(action: {
                    saveAPIService()
                }) {
                    Label("Save", systemImage: "checkmark")
                }
            }
            .padding(.top, 16)
        }
        .padding(16)
        .onAppear {
            selectedModel = model
            if apiService != nil, let serviceIDString = apiService?.id?.uuidString {
                do {
                    apiKey = try TokenManager.getToken(for: serviceIDString)!
                } catch {
                    print("Failed to get token: \(error.localizedDescription)")
                }
            }
        }
        .alert(isPresented: $showingDeleteConfirmation) {
            Alert(
                title: Text("Delete Persona"),
                message: Text("Are you sure you want to delete this API Service? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    deleteAPIService()
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    private func saveAPIService() {
        let APIServiceToSave = apiService ?? APIServiceEntity(context: viewContext)
        APIServiceToSave.name = name
        APIServiceToSave.type = type
        APIServiceToSave.url = URL(string: url)!
        APIServiceToSave.model = model
        APIServiceToSave.contextSize = Int16(contextSize)
        APIServiceToSave.useStreamResponse = useStreamResponse
        APIServiceToSave.generateChatNames = generateChatNames
        APIServiceToSave.defaultPersona = defaultAiPersona
        
        if (apiService == nil) {
            APIServiceToSave.addedDate = Date()
            let APIServiceID = UUID()
            APIServiceToSave.id = APIServiceID
            
            do {
                try TokenManager.setToken(apiKey, for: APIServiceID.uuidString)
            } catch {
                print("Error setting token: \(error)")
            }
            
        } else {
            APIServiceToSave.editedDate = Date()
        }
        
        do {
            APIServiceToSave.objectWillChange.send()
            try viewContext.save()
            presentationMode.wrappedValue.dismiss()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
    
    private func deleteAPIService() {
        viewContext.delete(apiService!)
        do {
            try viewContext.save()
            presentationMode.wrappedValue.dismiss()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
}
