//
//  ModelsCache.swift
//  macai
//
//  Created by Renat Notfullin on 07.07.2026.
//

import Foundation

/// Caches fetched model lists per API service so model pickers can show
/// content immediately while a background refresh runs.
final class ModelsCache {
    static let shared = ModelsCache()

    private let defaults: UserDefaults
    private var memoryCache: [UUID: [String]] = [:]
    private let queue = DispatchQueue(label: "com.macai.modelsCache")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func models(for serviceID: UUID) -> [String]? {
        queue.sync {
            if let cached = memoryCache[serviceID] {
                return cached
            }
            guard let stored = defaults.stringArray(forKey: Self.storageKey(for: serviceID)),
                  !stored.isEmpty
            else {
                return nil
            }
            memoryCache[serviceID] = stored
            return stored
        }
    }

    func store(_ models: [String], for serviceID: UUID) {
        guard !models.isEmpty else { return }
        queue.sync {
            memoryCache[serviceID] = models
            defaults.set(models, forKey: Self.storageKey(for: serviceID))
        }
    }

    func removeModels(for serviceID: UUID) {
        queue.sync {
            memoryCache.removeValue(forKey: serviceID)
            defaults.removeObject(forKey: Self.storageKey(for: serviceID))
        }
    }

    private static func storageKey(for serviceID: UUID) -> String {
        "cachedModels-\(serviceID.uuidString)"
    }
}
