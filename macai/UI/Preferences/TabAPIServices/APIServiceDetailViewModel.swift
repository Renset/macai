//
//  APIServiceDetailViewModel.swift
//  macai
//
//  Created by Renat Notfullin on 18.09.2024.
//

import Combine
import SwiftUI

class APIServiceDetailViewModel: ObservableObject {
    private let viewContext: NSManagedObjectContext
    var apiService: APIServiceEntity?
    private var cancellables = Set<AnyCancellable>()

    @Published var name: String = AppConstants.defaultApiConfigurations[AppConstants.defaultApiType]?.name ?? ""
    @Published var type: String = AppConstants.defaultApiType
    @Published var url: String = ""
    @Published var model: String = ""
    @Published var contextSize: Float = 20
    @Published var contextSizeUnlimited: Bool = false
    @Published var useStreamResponse: Bool = true
    @Published var generateChatNames: Bool = true
    @Published var defaultAiPersona: PersonaEntity?
    @Published var apiKey: String = ""
    @Published var isCustomModel: Bool = false
    @Published var selectedModel: String =
        (AppConstants.defaultApiConfigurations[AppConstants.defaultApiType]?.defaultModel ?? "")
    @Published var defaultApiConfiguration = AppConstants.defaultApiConfigurations[AppConstants.defaultApiType]
    @Published var fetchedModels: [AIModel] = []
    @Published var isLoadingModels: Bool = false
    @Published var modelFetchError: String? = nil

    init(viewContext: NSManagedObjectContext, apiService: APIServiceEntity?) {
        self.viewContext = viewContext
        self.apiService = apiService

        setupInitialValues()
        setupBindings()
        fetchModelsForService()
    }

    private func setupInitialValues() {
        if let service = apiService {
            name = service.name ?? defaultApiConfiguration!.name
            type = service.type ?? AppConstants.defaultApiType
            url = service.url?.absoluteString ?? ""
            model = service.model ?? ""
            contextSize = Float(service.contextSize)
            useStreamResponse = service.useStreamResponse
            generateChatNames = service.generateChatNames
            defaultAiPersona = service.defaultPersona
            defaultApiConfiguration = AppConstants.defaultApiConfigurations[type]
            selectedModel = model
            isCustomModel = ((defaultApiConfiguration!.models.contains(model)) == false)

            if let serviceIDString = service.id?.uuidString {
                do {
                    apiKey = try TokenManager.getToken(for: serviceIDString) ?? ""
                }
                catch {
                    print("Failed to get token: \(error.localizedDescription)")
                }
            }
        }
        else {
            url = AppConstants.apiUrlChatCompletions
        }
    }

    private func setupBindings() {
        $selectedModel
            .sink { [weak self] newValue in
                self?.isCustomModel = (newValue == "custom")
                if !self!.isCustomModel {
                    self?.model = newValue
                }
            }
            .store(in: &cancellables)
    }

    private func fetchModelsForService() {
        guard type.lowercased() == "ollama" || !apiKey.isEmpty else {
            fetchedModels = []
            return
        }

        isLoadingModels = true
        modelFetchError = nil

        let config = APIServiceConfig(
            name: type,
            apiUrl: URL(string: url)!,
            apiKey: apiKey,
            model: ""
        )

        let apiService = APIServiceFactory.createAPIService(config: config)

        Task {
            do {
                let models = try await apiService.fetchModels()
                DispatchQueue.main.async {
                    self.fetchedModels = models
                    self.isLoadingModels = false

                    if !models.contains(where: { $0.id == self.selectedModel }) {
                        self.selectedModel = models.first?.id ?? self.defaultApiConfiguration!.defaultModel
                    }
                }
            }
            catch {
                DispatchQueue.main.async {
                    self.modelFetchError = error.localizedDescription
                    self.isLoadingModels = false
                    self.fetchedModels = []
                }
            }
        }
    }

    var availableModels: [String] {
        if fetchedModels.isEmpty == false {
            return fetchedModels.map { $0.id }
        }
        else {
            return defaultApiConfiguration?.models ?? []
        }
    }

    func saveAPIService() {
        let serviceToSave = apiService ?? APIServiceEntity(context: viewContext)
        serviceToSave.name = name
        serviceToSave.type = type
        serviceToSave.url = URL(string: url)
        serviceToSave.model = model
        serviceToSave.contextSize = Int16(contextSize)
        serviceToSave.useStreamResponse = useStreamResponse
        serviceToSave.generateChatNames = generateChatNames
        serviceToSave.defaultPersona = defaultAiPersona

        if apiService == nil {
            serviceToSave.addedDate = Date()
            let serviceID = UUID()
            serviceToSave.id = serviceID
        }
        else {
            serviceToSave.editedDate = Date()
        }

        if let serviceIDString = serviceToSave.id?.uuidString {
            do {
                try TokenManager.setToken(apiKey, for: serviceIDString)
            }
            catch {
                print("Failed to set token: \(error.localizedDescription)")
            }
        }

        do {
            try viewContext.save()
        }
        catch {
            print("Error saving context: \(error)")
        }
    }

    func deleteAPIService() {
        guard let serviceToDelete = apiService else { return }
        viewContext.delete(serviceToDelete)
        do {
            try viewContext.save()
        }
        catch {
            print("Error deleting API service: \(error)")
        }
    }

    func onChangeApiType(_ type: String) {
        self.name = self.name == self.defaultApiConfiguration!.name ? "" : self.name
        self.defaultApiConfiguration = AppConstants.defaultApiConfigurations[type]
        self.name = self.name == "" ? self.defaultApiConfiguration!.name : self.name
        self.url = self.defaultApiConfiguration!.url
        self.model = self.defaultApiConfiguration!.defaultModel
        self.selectedModel = self.model

        fetchModelsForService()
    }

    func onChangeApiKey(_ token: String) {
        self.apiKey = token
        fetchModelsForService()
    }

    func onUpdateModelsList() {
        fetchModelsForService()
    }
}
