//
//  APIServiceDetailViewModel.swift
//  macai
//
//  Created by Renat Notfullin on 18.09.2024.
//

import CoreData
import SwiftUI

struct EditableHTTPHeader: Identifiable, Equatable {
    let id: UUID
    var name: String
    var value: String

    init(id: UUID = UUID(), name: String = "", value: String = "") {
        self.id = id
        self.name = name
        self.value = value
    }
}

@MainActor
class APIServiceDetailViewModel: ObservableObject {
    private let viewContext: NSManagedObjectContext
    var apiService: APIServiceEntity?

    @Published var name: String = AppConstants.defaultApiConfigurations[AppConstants.defaultApiType]?.name ?? ""
    @Published var type: String = AppConstants.defaultApiType
    @Published var url: String = ""
    @Published var imageUploadsAllowed: Bool = false
    @Published var pdfUploadsAllowed: Bool = false
    @Published var apiKey: String = ""
    @Published var customHeaders: [EditableHTTPHeader] = []
    @Published var defaultApiConfiguration = AppConstants.defaultApiConfigurations[AppConstants.defaultApiType]

    init(viewContext: NSManagedObjectContext, apiService: APIServiceEntity?, preferredType: String? = nil) {
        self.viewContext = viewContext
        self.apiService = apiService

        if apiService == nil,
           let preferredType,
           let configuration = AppConstants.defaultApiConfigurations[preferredType]
        {
            type = preferredType
            defaultApiConfiguration = configuration
            name = configuration.name
        }

        setupInitialValues()
    }

    private func setupInitialValues() {
        if let service = apiService {
            name = service.name ?? defaultApiConfiguration?.name ?? ""
            type = service.type ?? AppConstants.defaultApiType
            url = service.url?.absoluteString ?? ""
            imageUploadsAllowed = service.imageUploadsAllowed
            pdfUploadsAllowed = service.pdfUploadsAllowed
            defaultApiConfiguration = AppConstants.defaultApiConfigurations[type]

            if let serviceID = service.id {
                customHeaders = APIServiceHeaderStore.load(for: serviceID)
                    .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
                    .map { EditableHTTPHeader(name: $0.key, value: $0.value) }
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
                pdfUploadsAllowed = config.pdfUploadsSupported
                name = config.name
                defaultApiConfiguration = config
            }
            else {
                url = AppConstants.apiUrlOpenAIResponses
                imageUploadsAllowed = false
                pdfUploadsAllowed = false
            }
        }
    }

    var normalizedCustomHeaders: [String: String] {
        customHeaders.reduce(into: [:]) { result, header in
            let name = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = header.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !value.isEmpty else { return }
            result[name] = value
        }
    }

    var hasInvalidCustomHeaders: Bool {
        let completed = customHeaders.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard completed.allSatisfy({
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.name.contains(":")
                && !$0.name.contains(where: { $0.isWhitespace })
        }) else { return true }
        let names = completed.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return Set(names).count != names.count
    }

    func addCustomHeader() {
        customHeaders.append(EditableHTTPHeader())
    }

    func removeCustomHeader(id: UUID) {
        customHeaders.removeAll { $0.id == id }
    }

    func saveAPIService() {
        let serviceToSave = apiService ?? APIServiceEntity(context: viewContext)
        serviceToSave.name = name
        serviceToSave.type = type
        serviceToSave.url = URL(string: url)
        serviceToSave.imageUploadsAllowed = imageUploadsAllowed
        serviceToSave.pdfUploadsAllowed = pdfUploadsAllowed
        if serviceToSave.tokenIdentifier == nil || serviceToSave.tokenIdentifier?.isEmpty == true {
            serviceToSave.tokenIdentifier = UUID().uuidString
        }

        if let config = defaultApiConfiguration {
            serviceToSave.imageGenerationSupported = config.imageGenerationSupported
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
            try APIServiceHeaderStore.save(normalizedCustomHeaders, for: serviceID)
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

        let defaultRequest = NSFetchRequest<PersonaEntity>(entityName: "PersonaEntity")
        defaultRequest.predicate = NSPredicate(format: "isDefault == YES AND apiService == %@", serviceToDelete)
        if let removedDefault = try? viewContext.fetch(defaultRequest).first {
            removedDefault.isDefault = false
            let replacementRequest = NSFetchRequest<PersonaEntity>(entityName: "PersonaEntity")
            replacementRequest.predicate = NSPredicate(format: "apiService != nil AND apiService != %@", serviceToDelete)
            replacementRequest.sortDescriptors = [NSSortDescriptor(keyPath: \PersonaEntity.order, ascending: true)]
            replacementRequest.fetchLimit = 1
            (try? viewContext.fetch(replacementRequest).first)?.isDefault = true
        }

        if let serviceID = serviceToDelete.id {
            let serviceIDString = serviceID.uuidString
            try? TokenManager.deleteToken(for: serviceIDString)
            APIServiceHeaderStore.delete(for: serviceID)
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
        self.name = self.name == self.defaultApiConfiguration?.name ? "" : self.name
        self.defaultApiConfiguration = AppConstants.defaultApiConfigurations[type]
        self.name = self.name == "" ? (self.defaultApiConfiguration?.name ?? "") : self.name
        self.url = self.defaultApiConfiguration?.url ?? AppConstants.apiUrlOpenAIResponses
        self.imageUploadsAllowed = self.defaultApiConfiguration?.imageUploadsSupported ?? false
        self.pdfUploadsAllowed = self.defaultApiConfiguration?.pdfUploadsSupported ?? false
    }

    func onChangeApiKey(_ token: String) {
        self.apiKey = token
    }

    var supportsImageUploads: Bool {
        return AppConstants.defaultApiConfigurations[type]?.imageUploadsSupported ?? false
    }

    var supportsPdfUploads: Bool {
        return AppConstants.defaultApiConfigurations[type]?.pdfUploadsSupported ?? false
    }
}
