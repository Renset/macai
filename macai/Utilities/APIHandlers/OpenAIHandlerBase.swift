//
//  OpenAIHandlerBase.swift
//  macai
//
//  Created by Renat on 19.10.2025.
//

import CoreData
import Foundation

class OpenAIHandlerBase {
    let name: String
    let baseURL: URL
    let apiKey: String
    let model: String
    let imageGenerationSupported: Bool
    let session: URLSession

    init(config: APIServiceConfiguration, session: URLSession, imageGenerationSupported: Bool = false) {
        self.name = config.name
        self.baseURL = config.apiUrl
        self.apiKey = config.apiKey
        self.model = config.model
        self.imageGenerationSupported = imageGenerationSupported
        self.session = session
    }

    func handleAPIResponse(_ response: URLResponse?, data: Data?, error: Error?) -> Result<Data?, APIError> {
        if let error = error {
            return .failure(.requestFailed(error))
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure(.invalidResponse)
        }

        if !(200...299).contains(httpResponse.statusCode) {
            if let data = data, let errorResponse = String(data: data, encoding: .utf8) {
                switch httpResponse.statusCode {
                case 401:
                    return .failure(.unauthorized)
                case 429:
                    return .failure(.rateLimited)
                case 400...499:
                    return .failure(.serverError("Client Error: \(errorResponse)"))
                case 500...599:
                    return .failure(.serverError("Server Error: \(errorResponse)"))
                default:
                    return .failure(.unknown("Unknown error: \(errorResponse)"))
                }
            }
            else {
                return .failure(.serverError("HTTP \(httpResponse.statusCode)"))
            }
        }

        return .success(data)
    }

    func loadImageFromCoreData(uuid: UUID) -> Data? {
        let viewContext = PersistenceController.shared.container.viewContext

        let fetchRequest: NSFetchRequest<ImageEntity> = ImageEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
        fetchRequest.fetchLimit = 1

        do {
            let results = try viewContext.fetch(fetchRequest)
            if let imageEntity = results.first, let imageData = imageEntity.image {
                return imageData
            }
        }
        catch {
            print("Error fetching image from CoreData: \(error)")
        }

        return nil
    }

    struct FileAttachmentPayload {
        let data: Data
        let filename: String?
        let mimeType: String?
    }

    func loadFileFromCoreData(uuid: UUID) -> FileAttachmentPayload? {
        let viewContext = PersistenceController.shared.container.viewContext

        let fetchRequest: NSFetchRequest<DocumentEntity> = DocumentEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
        fetchRequest.fetchLimit = 1

        do {
            let results = try viewContext.fetch(fetchRequest)
            if let documentEntity = results.first, let fileData = documentEntity.fileData {
                return FileAttachmentPayload(
                    data: fileData,
                    filename: documentEntity.filename,
                    mimeType: documentEntity.mimeType
                )
            }
        }
        catch {
            print("Error fetching file from CoreData: \(error)")
        }

        return nil
    }

    func isNotSSEComment(_ string: String) -> Bool {
        return !string.starts(with: ":")
    }
}
