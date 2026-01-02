//
//  APIServiceDetailViewModel.swift
//  macai
//
//  Created by Renat Notfullin on 18.09.2024.
//

import Combine
import CoreData
import SwiftUI

@MainActor
class APIServiceDetailViewModel: ObservableObject {
    private let viewContext: NSManagedObjectContext
    var apiService: APIServiceEntity?
    private var cancellables = Set<AnyCancellable>()
    private var hasProcessedInitialModelSelection = false

    @Published var name: String = AppConstants.defaultApiConfigurations[AppConstants.defaultApiType]?.name ?? ""
    @Published var type: String = AppConstants.defaultApiType
    @Published var url: String = ""
    @Published var model: String = ""
    @Published var contextSize: Float = 20
    @Published var contextSizeUnlimited: Bool = false
    @Published var useStreamResponse: Bool = true
    @Published var generateChatNames: Bool = true
    @Published var imageUploadsAllowed: Bool = false
    @Published var imageGenerationSupported: Bool = false
    @Published var defaultAiPersona: PersonaEntity?
    @Published var apiKey: String = ""
    @Published var isCustomModel: Bool = false
    @Published var selectedModel: String =
        (AppConstants.defaultApiConfigurations[AppConstants.defaultApiType]?.defaultModel ?? "")
    @Published var defaultApiConfiguration = AppConstants.defaultApiConfigurations[AppConstants.defaultApiType]
    @Published var fetchedModels: [AIModel] = []
    @Published var isLoadingModels: Bool = false
    @Published var modelFetchError: String? = nil

    init(viewContext: NSManagedObjectContext, apiService: APIServiceEntity?, preferredType: String? = nil) {
        self.viewContext = viewContext
        self.apiService = apiService

        if apiService == nil,
           let preferredType,
           let configuration = AppConstants.defaultApiConfigurations[preferredType]
        {
            type = preferredType
            defaultApiConfiguration = configuration
            selectedModel = configuration.defaultModel
            model = configuration.defaultModel
            name = configuration.name
        }

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
            imageUploadsAllowed = service.imageUploadsAllowed
            imageGenerationSupported = service.imageGenerationSupported
            defaultAiPersona = service.defaultPersona
            defaultApiConfiguration = AppConstants.defaultApiConfigurations[type]
            selectedModel = model

            if let serviceID = service.id {
                let serviceIDString = serviceID.uuidString
                do {
                    apiKey = try TokenManager.getToken(for: serviceIDString) ?? ""
                }
                catch {
                    print("Failed to get token: \(error.localizedDescription)")
                }
            }
        }
        else {
            if let config = AppConstants.defaultApiConfigurations[type] {
                url = config.url
                imageUploadsAllowed = config.imageUploadsSupported
                let selected = selectedModel.isEmpty ? config.defaultModel : selectedModel
                imageGenerationSupported = Self.supportedState(
                    for: selected,
                    using: config
                )
                name = config.name
                model = selected
                selectedModel = selected
                defaultApiConfiguration = config
            }
            else {
                url = AppConstants.apiUrlOpenAIResponses
                imageUploadsAllowed = false
                imageGenerationSupported = false
            }
        }
    }

    private func setupBindings() {
        $selectedModel
            .sink { [weak self] newValue in
                guard let self else { return }
                self.isCustomModel = (newValue == "custom")
                if !self.isCustomModel {
                    self.model = newValue
                }

                guard let config = self.defaultApiConfiguration else { return }

                if self.hasProcessedInitialModelSelection == false {
                    self.hasProcessedInitialModelSelection = true
                    return
                }

                if Self.supportedState(for: newValue, using: config) {
                    self.imageGenerationSupported = true
                }
            }
            .store(in: &cancellables)
    }

    private func fetchModelsForService() {
        isLoadingModels = true
        modelFetchError = nil

        let config = APIServiceConfig(
            name: type,
            apiUrl: URL(string: url)!,
            apiKey: apiKey,
            model: ""
        )

        let apiService = APIServiceFactory.createAPIService(
            config: config,
            imageGenerationSupported: imageGenerationSupported
        )

        Task {
            do {
                let models = try await apiService.fetchModels()
                self.fetchedModels = models
                self.isLoadingModels = false
                self.updateModelSelection()
            }
            catch {
                self.modelFetchError = error.localizedDescription
                self.isLoadingModels = false
                self.fetchedModels = []
                self.updateModelSelection()
            }
        }
    }
    
    private func updateModelSelection() {
        let modelExists = self.availableModels.contains(self.selectedModel)
        
        if !modelExists && !self.selectedModel.isEmpty {
            self.isCustomModel = true
            self.selectedModel = "custom"
        } else if modelExists {
            self.isCustomModel = false
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
        serviceToSave.imageUploadsAllowed = imageUploadsAllowed
        serviceToSave.imageGenerationSupported = imageGenerationSupported
        serviceToSave.defaultPersona = defaultAiPersona
        if serviceToSave.tokenIdentifier == nil || serviceToSave.tokenIdentifier?.isEmpty == true {
            serviceToSave.tokenIdentifier = UUID().uuidString
        }

        if apiService == nil {
            serviceToSave.addedDate = Date()
            serviceToSave.id = UUID()
        }
        else {
            serviceToSave.editedDate = Date()
        }

        guard let serviceID = serviceToSave.id else {
            print("Failed to set token: missing service id")
            return
        }

        let serviceIDString = serviceID.uuidString
        do {
            try TokenManager.setToken(apiKey, for: serviceIDString)
        }
        catch {
            print("Failed to set token: \(error.localizedDescription)")
        }

        if serviceToSave.objectID.isTemporaryID {
            do {
                try viewContext.obtainPermanentIDs(for: [serviceToSave])
            }
            catch {
                print("Failed to obtain permanent ID for API service: \(error)")
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

        if let serviceID = serviceToDelete.id {
            let serviceIDString = serviceID.uuidString
            try? TokenManager.deleteToken(for: serviceIDString)
        }

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

        self.imageUploadsAllowed = self.defaultApiConfiguration!.imageUploadsSupported
        self.imageGenerationSupported = Self.supportedState(
            for: self.model,
            using: self.defaultApiConfiguration!
        )

        self.hasProcessedInitialModelSelection = false

        fetchModelsForService()
    }

    func onChangeApiKey(_ token: String) {
        self.apiKey = token
        fetchModelsForService()
    }

    func onUpdateModelsList() {
        fetchModelsForService()
    }

    var supportsImageUploads: Bool {
        return AppConstants.defaultApiConfigurations[type]?.imageUploadsSupported ?? false
    }

    var supportsImageGeneration: Bool {
        let configSupports = AppConstants.defaultApiConfigurations[type]?.imageGenerationSupported ?? false
        return configSupports || imageGenerationSupported
    }

    private static func supportedState(
        for model: String,
        using config: AppConstants.defaultApiConfiguration
    ) -> Bool {
        guard config.imageGenerationSupported else { return false }
        return config.autoEnableImageGenerationModels.contains(model)
    }
}
