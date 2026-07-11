//
//  APIServiceDetailView.swift
//  macai
//
//  Created by Renat Notfullin on 13.09.2024.
//
import CoreData
import SwiftUI

struct APIServiceDetailView: View {
    @StateObject private var viewModel: APIServiceDetailViewModel
    @Environment(\.presentationMode) var presentationMode
    @State private var lampColor: Color = .gray
    @State private var showingDeleteConfirmation: Bool = false
    @FocusState private var isFocused: Bool
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \PersonaEntity.addedDate, ascending: true)],
        animation: .default
    )
    private var personas: FetchedResults<PersonaEntity>

    init(viewContext: NSManagedObjectContext, apiService: APIServiceEntity?, preferredType: String? = nil) {
        let viewModel = APIServiceDetailViewModel(
            viewContext: viewContext,
            apiService: apiService,
            preferredType: preferredType
        )
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    private let types = AppConstants.apiTypes

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Service Name:")
                    .frame(width: 100, alignment: .leading)

                TextField("API Name", text: $viewModel.name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            GroupBox {
                VStack {
                    VStack {
                        HStack {
                            Text("API Type:")
                                .frame(width: 100, alignment: .leading)

                            Image("logo_\(viewModel.type)")
                                .resizable()
                                .renderingMode(.template)
                                .interpolation(.high)
                                .antialiased(true)
                                .frame(width: 14, height: 14)

                            Picker("", selection: $viewModel.type) {
                                ForEach(types, id: \.self) {
                                    Text(AppConstants.defaultApiConfigurations[$0]?.name ?? $0)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onChange(of: viewModel.type) { _, newValue in
                                viewModel.onChangeApiType(newValue)
                            }
                        }
                    }
                    .padding(.bottom, 8)

                    HStack {
                        Text("API URL:")
                            .frame(width: 100, alignment: .leading)

                        TextField("Paste your URL here", text: $viewModel.url)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button(action: {
                            viewModel.url = viewModel.defaultApiConfiguration?.url ?? AppConstants.apiUrlOpenAIResponses
                        }) {
                            Text("Default")
                        }
                    }

                    if (viewModel.defaultApiConfiguration?.apiKeyRef ?? "") != "" {
                        HStack {
                            Text("API Key:")
                                .frame(width: 100, alignment: .leading)

                            TextField("Paste your key here", text: $viewModel.apiKey)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .focused($isFocused)
                                .blur(radius: !viewModel.apiKey.isEmpty && !isFocused ? 3 : 0.0, opaque: false)
                                .onChange(of: viewModel.apiKey) { _, newValue in
                                    viewModel.onChangeApiKey(newValue)
                                }
                        }

                        if let apiKeyRefURL = URL(string: viewModel.defaultApiConfiguration?.apiKeyRef ?? "") {
                            HStack {
                                Spacer()
                                Link("How to get API Key", destination: apiKeyRefURL)
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                            }
                        }
                    }

                    HStack {
                        ButtonTestApiTokenAndModel(
                            lampColor: $lampColor,
                            gptToken: viewModel.apiKey,
                            gptModel: viewModel.testModel,
                            apiUrl: viewModel.url,
                            apiType: viewModel.type,
                            imageGenerationSupported: viewModel.testImageGenerationEnabled,
                            customHeaders: viewModel.normalizedCustomHeaders
                        )
                    }
                }
                .padding(8)
            }

            VStack {
                if viewModel.supportsImageUploads {
                    Toggle(isOn: $viewModel.imageUploadsAllowed) {
                        HStack {
                            Text("Allow image uploads")
                            Button(action: {
                            }) {
                                Image(systemName: "questionmark.circle")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help(
                                "If enabled, you can upload images to be processed by the AI. PDFs are supported for OpenAI Responses and Gemini models."
                            )

                            Spacer()
                        }
                    }
                }

                if viewModel.supportsPdfUploads {
                    Toggle(isOn: $viewModel.pdfUploadsAllowed) {
                        HStack {
                            Text("Allow PDF uploads")
                            Button(action: {
                            }) {
                                Image(systemName: "questionmark.circle")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help(
                                "If enabled, you can upload PDF documents to be processed by the AI."
                            )

                            Spacer()
                        }
                    }
                }
            }
            .padding(.vertical, 8)

            DisclosureGroup("Advanced") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach($viewModel.customHeaders) { $header in
                        HStack {
                            TextField("Header name", text: $header.name)
                            TextField("Value", text: $header.value)
                            Button("Remove header", systemImage: "minus.circle", role: .destructive) {
                                viewModel.removeCustomHeader(id: header.id)
                            }
                            .labelStyle(.iconOnly)
                        }
                    }

                    Button("Add Header", systemImage: "plus") {
                        viewModel.addCustomHeader()
                    }
                    .buttonStyle(.link)

                    Text("Custom headers are stored securely in Keychain. Required provider headers take precedence.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if viewModel.hasInvalidCustomHeaders {
                        Text("Enter a unique name and value for each header. Names cannot contain spaces or colons.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.top, 8)
            }

            HStack {
                Text("Default AI Assistant:")
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
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.hasInvalidCustomHeaders)
            }
            .padding(.top, 16)
        }
        .padding(16)
        .alert(isPresented: $showingDeleteConfirmation) {
            Alert(
                title: Text("Delete Assistant"),
                message: Text("Are you sure you want to delete this API Service? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    viewModel.deleteAPIService()
                    presentationMode.wrappedValue.dismiss()
                },
                secondaryButton: .cancel()
            )
        }
    }
}
