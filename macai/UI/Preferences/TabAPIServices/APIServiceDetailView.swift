//
//  APIServiceDetailView.swift
//  macai
//
//  Created by Renat Notfullin on 13.09.2024.
//
import SwiftUI

struct APIServiceDetailView: View {
    @StateObject private var viewModel: APIServiceDetailViewModel
    @Environment(\.presentationMode) var presentationMode
    @State private var lampColor: Color = .gray
    @State private var showingDeleteConfirmation: Bool = false
    @FocusState private var isFocused: Bool
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \PersonaEntity.addedDate, ascending: true)],
        animation: .default)
    private var personas: FetchedResults<PersonaEntity>
    
    init(viewContext: NSManagedObjectContext, apiService: APIServiceEntity?) {
        let viewModel = APIServiceDetailViewModel(viewContext: viewContext, apiService: apiService)
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    private let types = AppConstants.apiTypes
    @State private var previousModel = ""

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
                        Picker("API Type", selection: $viewModel.type) {
                            ForEach(types, id: \.self) {
                                Text($0)
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
                
                HStack {
                    Text("API Name:")
                        .frame(width: 100, alignment: .leading)

                    TextField("API Name", text: $viewModel.name)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                
                HStack {
                    Text("API URL:")
                        .frame(width: 100, alignment: .leading)

                    TextField("Paste your URL here", text: $viewModel.url)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Button(action: {
                        viewModel.url = AppConstants.apiUrlChatCompletions
                    }) {
                        Text("Default")
                    }
                }
                

                HStack {
                    Text("API Token:")
                        .frame(width: 100, alignment: .leading)

                    TextField("Paste your token here", text: $viewModel.apiKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($isFocused)
                        .blur(radius: !viewModel.apiKey.isEmpty && !isFocused ? 3 : 0.0, opaque: false)
                        .onChange(of: viewModel.apiKey) { newValue in
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
                    value: $viewModel.contextSize,
                    in: 5...100,
                    step: 5
                ) {
                    Text("Context size")
                } minimumValueLabel: {
                    Text("5")
                } maximumValueLabel: {
                    Text("100")
                }

                Text(String(format: ("%.0f messages"), viewModel.contextSize))
                    .frame(width: 90)
            }
            .padding(.top, 16)

            VStack {
                Toggle(isOn: $viewModel.generateChatNames) {
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
                Toggle(isOn: $viewModel.useStreamResponse) {
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

                Picker("", selection: $viewModel.selectedModel) {
                    ForEach(AppConstants.predefinedModels[viewModel.type ?? "chatgpt"] ?? [], id: \.self) { modelName in
                        Text(modelName).tag(modelName)
                    }
                    Text("Enter custom model").tag("custom")
                }.onChange(of: viewModel.selectedModel) { newValue in
                    if (newValue == "custom") {
                        viewModel.isCustomModel = true
                    } else {
                        viewModel.isCustomModel = false
                        viewModel.model = newValue
                    }

                    if viewModel.model != self.previousModel {
                        self.lampColor = .gray
                        self.previousModel = viewModel.model
                    }
                }
            }

        if (viewModel.isCustomModel) {
            VStack {
                TextField("Enter custom model name", text: $viewModel.model)
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
                Text("Default AI Persona:")
                    .frame(width: 160, alignment: .leading)
                
                Picker("", selection: $viewModel.defaultAiPersona) {
                    ForEach(personas) { persona in
                        Text(persona.name ?? "Untitled").tag(persona)
                    }
                }
            }
            
            HStack {
                if viewModel.apiService != nil {
                    Button(action: {
                        showingDeleteConfirmation = true
                    }) {
                        Label("Delete", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                }
                Spacer()
                ButtonTestApiTokenAndModel(lampColor: $lampColor, gptToken: viewModel.apiKey, gptModel: viewModel.model, apiUrl: viewModel.url)
                
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Cancel")
                }
                
                Button(action: {
                    viewModel.saveAPIService()
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Save")
                }
            }
            .padding(.top, 16)
        }
        .padding(16)
        .alert(isPresented: $showingDeleteConfirmation) {
            Alert(
                title: Text("Delete Persona"),
                message: Text("Are you sure you want to delete this API Service? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    viewModel.deleteAPIService()
                },
                secondaryButton: .cancel()
            )
        }
    }
}
