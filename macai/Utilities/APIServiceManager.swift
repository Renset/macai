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
    
    func createAPIService(name: String, type: String, url: URL, model: String, contextSize: Int16, useStreamResponse: Bool, generateChatNames: Bool) -> APIServiceEntity {
        let apiService = APIServiceEntity(context: viewContext)
        apiService.id = UUID()
        apiService.name = name
        apiService.type = type
        apiService.url = url
        apiService.model = model
        apiService.contextSize = contextSize
        apiService.useStreamResponse = useStreamResponse
        apiService.generateChatNames = generateChatNames
        apiService.tokenIdentifier = UUID().uuidString
        
        do {
            try viewContext.save()
        } catch {
            print("Error saving API service: \(error)")
        }
        
        return apiService
    }
    
    func updateAPIService(_ apiService: APIServiceEntity, name: String, type: String, url: URL, model: String, contextSize: Int16, useStreamResponse: Bool, generateChatNames: Bool) {
        apiService.name = name
        apiService.type = type
        apiService.url = url
        apiService.model = model
        apiService.contextSize = contextSize
        apiService.useStreamResponse = useStreamResponse
        apiService.generateChatNames = generateChatNames
        
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
