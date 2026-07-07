//
//  ApiServiceManager.swift
//  macai
//
//  Created by Renat Notfullin on 12.09.2024.
//

import Foundation
import CoreData

class APIServiceManager {
    private let viewContext: NSManagedObjectContext
    
    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
    }
    
    func createAPIService(
        name: String,
        type: String,
        url: URL,
        imageUploadsAllowed: Bool,
        pdfUploadsAllowed: Bool,
        imageGenerationSupported: Bool
    ) -> APIServiceEntity {
        let apiService = APIServiceEntity(context: viewContext)
        apiService.id = UUID()
        apiService.name = name
        apiService.type = type
        apiService.url = url
        apiService.imageUploadsAllowed = imageUploadsAllowed
        apiService.pdfUploadsAllowed = pdfUploadsAllowed
        apiService.imageGenerationSupported = imageGenerationSupported
        apiService.tokenIdentifier = UUID().uuidString
        
        do {
            try viewContext.save()
        } catch {
            print("Error saving API service: \(error)")
        }
        
        return apiService
    }
    
    func updateAPIService(
        _ apiService: APIServiceEntity,
        name: String,
        type: String,
        url: URL,
        imageUploadsAllowed: Bool,
        pdfUploadsAllowed: Bool,
        imageGenerationSupported: Bool
    ) {
        apiService.name = name
        apiService.type = type
        apiService.url = url
        apiService.imageUploadsAllowed = imageUploadsAllowed
        apiService.pdfUploadsAllowed = pdfUploadsAllowed
        apiService.imageGenerationSupported = imageGenerationSupported
        
        do {
            try viewContext.save()
        } catch {
            print("Error updaring API service: \(error)")
        }
    }
    
    func deleteAPIService(_ apiService: APIServiceEntity) {
        viewContext.delete(apiService)
        
        do {
            try viewContext.save()
        } catch {
            print("Error deleting API service: \(error)")
        }
    }
    
    func getAllAPIServices() -> [APIServiceEntity] {
        let fetchRequest: NSFetchRequest<APIServiceEntity> = APIServiceEntity.fetchRequest()
        
        do {
            return try viewContext.fetch(fetchRequest)
        } catch {
            print("Error fetching API services: \(error)")
            return []
        }
    }
    
    func getAPIService(withID id: UUID) -> APIServiceEntity? {
        let fetchRequest: NSFetchRequest<APIServiceEntity> = APIServiceEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            return results.first
        } catch {
            print("Error fetching API service: \(error)")
            return nil
        }
    }
}

extension APIServiceManager {
    static func fetchRemoteModels(
        context: NSManagedObjectContext,
        serviceID: NSManagedObjectID
    ) async -> [String]? {
        var snapshot: (
            type: String,
            url: URL,
            serviceID: UUID,
            defaultModel: String,
            imageGenerationSupported: Bool
        )?

        context.performAndWait {
            guard let service = try? context.existingObject(with: serviceID) as? APIServiceEntity else {
                return
            }
            guard let type = service.type,
                  let url = service.url,
                  let id = service.id else {
                return
            }
            guard let config = AppConstants.defaultApiConfigurations[type],
                  config.modelsFetching else {
                return
            }
            snapshot = (
                type: type,
                url: url,
                serviceID: id,
                defaultModel: config.defaultModel,
                imageGenerationSupported: service.imageGenerationSupported
            )
        }

        guard let snapshot else {
            return nil
        }

        let apiKey = (try? TokenManager.getToken(for: snapshot.serviceID.uuidString)) ?? ""
        if apiKey.isEmpty {
            return nil
        }

        let apiConfig = APIServiceConfig(
            name: snapshot.type,
            apiUrl: snapshot.url,
            apiKey: apiKey,
            model: snapshot.defaultModel
        )

        let handler = APIServiceFactory.createAPIService(
            config: apiConfig,
            imageGenerationSupported: snapshot.imageGenerationSupported
        )

        do {
            let models = try await handler.fetchModels()
            let ids = models.map { $0.id }.filter { $0.isEmpty == false }.sorted()
            ModelsCache.shared.store(ids, for: snapshot.serviceID)
            return ids
        } catch {
            print("Failed to fetch models for \(snapshot.type): \(error)")
            return nil
        }
    }
}
