//
//  APIServiceTemplateAddViewModel.swift
//  macai
//
//  Created by Renat Notfullin on 19.09.2025
//

import CoreData
import SwiftUI

enum APIServiceTemplateExpertDestination {
    case new(preferredType: String?)
    case existing(NSManagedObjectID)
}

@MainActor
final class APIServiceTemplateAddViewModel: ObservableObject {
    enum Step: Int {
        case selectTemplate = 0
        case configure
        case validate
    }

    enum ValidationState: Equatable {
        case idle
        case running
        case success
        case failure(String)
    }

    struct TemplateOption: Identifiable, Equatable {
        let provider: APIServiceProviderTemplate
        let model: APIServiceModelTemplate

        var id: String { "\(provider.id)::\(model.id)" }

        static func == (lhs: TemplateOption, rhs: TemplateOption) -> Bool {
            lhs.id == rhs.id
        }
    }

    private let viewContext: NSManagedObjectContext

    // Template data
    @Published private(set) var providers: [APIServiceProviderTemplate] = []

    // Flow state
    @Published var currentStep: Step = .selectTemplate
    @Published var selectedProviderID: String = ""
    @Published var selectedModelID: String = ""
    @Published var selectedOptionID: String = ""

    // Configuration form
    @Published var serviceName: String = ""
    @Published var apiKey: String = ""
    @Published var selectedPersona: PersonaEntity?
    @Published var errorMessage: String?

    // Persisted settings (not directly exposed in the simple UI)
    private(set) var type: String = AppConstants.defaultApiType
    private(set) var url: String = AppConstants.apiUrlOpenAIResponses
    private(set) var model: String = AppConstants.defaultPrimaryModel
    private(set) var contextSize: Float = 20
    private(set) var generateChatNames: Bool = true
    private(set) var useStreamResponse: Bool = true
    private(set) var imageUploadsAllowed: Bool = false
    private(set) var imageGenerationSupported: Bool = false
    private(set) var defaultApiConfiguration = AppConstants.defaultApiConfigurations[AppConstants.defaultApiType]

    // Persistence / validation state
    @Published private(set) var isSaving: Bool = false
    @Published private(set) var createdServiceID: NSManagedObjectID?
    @Published private(set) var validationState: ValidationState = .idle
    @Published private(set) var isTesting: Bool = false
    @Published private(set) var validationMessage: String?

    init(viewContext: NSManagedObjectContext, defaultPersona: PersonaEntity? = nil) {
        self.viewContext = viewContext
        self.selectedPersona = defaultPersona

        let catalog = APIServiceTemplateProvider.loadCatalog()
        self.providers = catalog.providers

        if let firstOption = templateOptions.first {
            applySelection(option: firstOption, allowNameOverride: true)
        }
    }

    // MARK: - Derived Data

    var templateOptions: [TemplateOption] {
        providers.flatMap { provider in
            provider.models.map { TemplateOption(provider: provider, model: $0) }
        }
    }

    var selectedProvider: APIServiceProviderTemplate? {
        providers.first(where: { $0.id == selectedProviderID })
    }

    var selectedModel: APIServiceModelTemplate? {
        selectedProvider?.models.first(where: { $0.id == selectedModelID })
    }

    var selectedOption: TemplateOption? {
        guard let provider = selectedProvider, let model = selectedModel else { return nil }
        return TemplateOption(provider: provider, model: model)
    }

    var selectedNote: String? {
        selectedModel?.note ?? selectedProvider?.note
    }

    var createdServiceURIString: String? {
        guard let objectID = createdServiceID else { return nil }
        return objectID.uriRepresentation().absoluteString
    }

    var canAdvanceFromSelection: Bool {
        !selectedOptionID.isEmpty
    }

    var canAdvanceFromConfiguration: Bool {
        guard let provider = selectedProvider, let model = selectedModel else { return false }
        if model.requiresExpertMode { return false }
        if serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if requiresApiKey(for: provider) && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return !isSaving
    }

    var validationSucceeded: Bool {
        if case .success = validationState { return true }
        return false
    }

    // MARK: - Selection

    func selectOption(_ option: TemplateOption) {
        applySelection(option: option, allowNameOverride: true)
    }

    func selectOptionIfNeeded() {
        if let option = selectedOption {
            applySelection(option: option, allowNameOverride: false)
        }
    }

    private func applySelection(option: TemplateOption, allowNameOverride: Bool) {
        selectedProviderID = option.provider.id
        selectedModelID = option.model.id
        selectedOptionID = option.id

        type = option.provider.id
        defaultApiConfiguration = AppConstants.defaultApiConfigurations[type]
        url = defaultApiConfiguration?.url ?? AppConstants.apiUrlOpenAIResponses
        model = option.model.id

        updateSettings(from: option.model.settings)

        if allowNameOverride {
            applySuggestedName(provider: option.provider, model: option.model)
        }
    }

    private func updateSettings(from settings: APIServiceTemplateSettings?) {
        contextSize = Float(settings?.contextSize ?? 20)
        generateChatNames = settings?.generateChatNames ?? true
        useStreamResponse = settings?.useStreaming ?? true

        if let uploads = settings?.allowImageUploads {
            imageUploadsAllowed = uploads
        } else {
            imageUploadsAllowed = defaultApiConfiguration?.imageUploadsSupported ?? false
        }

        if let generation = settings?.imageGenerationSupported {
            imageGenerationSupported = generation
        } else if let config = defaultApiConfiguration {
            imageGenerationSupported = config.imageGenerationSupported
                && config.autoEnableImageGenerationModels.contains(model)
        } else {
            imageGenerationSupported = false
        }
    }

    func handleNameChange(_ newValue: String) {
        serviceName = newValue
    }

    func resetNameSuggestion() {
        guard let option = selectedOption else { return }
        applySuggestedName(provider: option.provider, model: option.model)
    }

    private func applySuggestedName(provider: APIServiceProviderTemplate, model: APIServiceModelTemplate?) {
        let suggestion: String
        if let defaultName = provider.defaultName, model?.id == provider.defaultModel?.id {
            suggestion = defaultName
        } else {
            let modelName = model?.displayName ?? model?.id ?? ""
            suggestion = modelName.isEmpty ? provider.displayName : modelName
        }
        serviceName = suggestion.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Navigation

    func advanceFromSelection() -> APIServiceTemplateExpertDestination? {
        guard canAdvanceFromSelection, let provider = selectedProvider, let model = selectedModel else { return nil }

        if model.requiresExpertMode {
            return .new(preferredType: provider.id)
        }

        errorMessage = nil
        currentStep = .configure
        return nil
    }

    func advanceFromConfiguration() -> Bool {
        guard persistService() else { return false }
        transitionToValidation()
        return true
    }

    func goBack() {
        switch currentStep {
        case .selectTemplate:
            break
        case .configure:
            currentStep = .selectTemplate
            errorMessage = nil
        case .validate:
            currentStep = .configure
            validationState = .idle
            validationMessage = nil
        }
    }

    func expertDestinationForCreatedService() -> APIServiceTemplateExpertDestination? {
        guard let objectID = createdServiceID else { return nil }
        return .existing(objectID)
    }

    private func transitionToValidation() {
        validationState = .idle
        validationMessage = nil
        currentStep = .validate
        startValidation()
    }

    // MARK: - Persistence

    @discardableResult
    func persistService() -> Bool {
        guard let provider = selectedProvider else {
            errorMessage = "Select an API provider to continue."
            return false
        }

        guard let modelTemplate = selectedModel else {
            errorMessage = "Select a model to continue."
            return false
        }

        if modelTemplate.requiresExpertMode {
            errorMessage = "This template needs Expert mode."
            return false
        }

        let trimmedName = serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Enter a name for the service."
            return false
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if requiresApiKey(for: provider) && trimmedKey.isEmpty {
            errorMessage = "Enter an API key before continuing."
            return false
        }

        guard let configuration = AppConstants.defaultApiConfigurations[provider.id] else {
            errorMessage = "Missing configuration for \(provider.displayName)."
            return false
        }

        guard let apiURL = URL(string: configuration.url) else {
            errorMessage = "The configured API URL is invalid."
            return false
        }

        isSaving = true
        defer { isSaving = false }

        let service: APIServiceEntity
        let isNewService: Bool

        if let existingID = createdServiceID,
           let existingObject = try? viewContext.existingObject(with: existingID) as? APIServiceEntity
        {
            service = existingObject
            isNewService = false
            service.editedDate = Date()
        } else {
            service = APIServiceEntity(context: viewContext)
            service.addedDate = Date()
            service.id = UUID()
            service.tokenIdentifier = UUID().uuidString
            isNewService = true
        }

        service.name = trimmedName
        service.type = provider.id
        service.url = apiURL
        service.model = modelTemplate.id
        service.contextSize = Int16(contextSize)
        service.useStreamResponse = useStreamResponse
        service.generateChatNames = generateChatNames
        service.imageUploadsAllowed = imageUploadsAllowed
        service.imageGenerationSupported = imageGenerationSupported
        service.defaultPersona = selectedPersona
        if service.tokenIdentifier == nil || service.tokenIdentifier?.isEmpty == true {
            service.tokenIdentifier = UUID().uuidString
        }
        if service.id == nil {
            service.id = UUID()
        }

        do {
            let identifier = service.id?.uuidString ?? UUID().uuidString
            service.id = UUID(uuidString: identifier) ?? service.id

            try TokenManager.setToken(trimmedKey, for: identifier)
            try viewContext.save()
            createdServiceID = service.objectID
            apiKey = trimmedKey
            errorMessage = nil
            return true
        }
        catch let tokenError as TokenManager.TokenError {
            if isNewService {
                viewContext.delete(service)
            }
            viewContext.rollback()

            switch tokenError {
            case .setFailed:
                errorMessage = "Failed to store the API key in the Keychain."
            case .getFailed, .deleteFailed:
                errorMessage = "Keychain access failed."
            }
            return false
        }
        catch {
            if isNewService {
                viewContext.delete(service)
            }
            viewContext.rollback()
            errorMessage = "Failed to save service. Please try again."
            return false
        }
    }

    private func requiresApiKey(for provider: APIServiceProviderTemplate) -> Bool {
        guard let configuration = AppConstants.defaultApiConfigurations[provider.id] else { return true }
        return configuration.apiKeyRef.isEmpty == false
    }

    // MARK: - Validation

    private func startValidation() {
        guard validationState == .idle else { return }

        validationState = .running
        isTesting = true
        validationMessage = "Testing connection..."

        guard let apiURL = URL(string: url) else {
            validationState = .failure("Invalid API URL")
            isTesting = false
            return
        }

        let config = APIServiceConfig(
            name: type,
            apiUrl: apiURL,
            apiKey: apiKey,
            model: model
        )
        let apiService = APIServiceFactory.createAPIService(
            config: config,
            imageGenerationSupported: imageGenerationSupported
        )
        let messageManager = MessageManager(apiService: apiService, viewContext: viewContext)

        messageManager.testAPI(model: model) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isTesting = false
                switch result {
                case .success:
                    self.validationState = .success
                    if let provider = self.selectedProvider, let model = self.selectedModel {
                        self.validationMessage = "Connected to \(provider.displayName) – \(model.displayName)."
                    } else {
                        self.validationMessage = "Connection test successful."
                    }
                case .failure(let error):
                    self.validationState = .failure(self.describe(apiError: error))
                }
            }
        }
    }

    private func describe(apiError: Error) -> String {
        if let apiError = apiError as? APIError {
            switch apiError {
            case .requestFailed(let error):
                return error.localizedDescription
            case .invalidResponse:
                return "The service returned an invalid response."
            case .decodingFailed(let message):
                return message
            case .unauthorized:
                return "Unauthorized. Check that your API key is correct."
            case .rateLimited:
                return "The service rate limited the request. Try again in a moment."
            case .serverError(let message):
                return message
            case .unknown(let message):
                return message
            case .noApiService(let message):
                return message
            }
        }
        return apiError.localizedDescription
    }
}
