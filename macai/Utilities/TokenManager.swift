//
//  TokenManager.swift
//  macai
//
//  Created by Renat Notfullin on 03.09.2024.
//

import Foundation
import KeychainAccess

final class TokenManager {
    private static let keychainService = "notfullin.com.macai"
    private static let tokenPrefix = "api_token_"

    // Local (non‑synchronizable) keychain used when iCloud sync is off
    private static var localKeychain: Keychain {
        Keychain(service: keychainService)
            .synchronizable(false)
            .accessibility(.afterFirstUnlock)
    }

    // iCloud‑backed keychain used when iCloud sync is on
    private static var cloudKeychain: Keychain {
        Keychain(service: keychainService)
            .synchronizable(true)
            .accessibility(.afterFirstUnlock)
    }

    enum TokenError: Error {
        case setFailed
        case getFailed
        case deleteFailed
    }

    // MARK: - Public API

    static func setToken(_ token: String, for service: String, identifier: String? = nil) throws {
        let key = makeKey(for: service, identifier: identifier)
        let syncEnabled = UserDefaults.standard.bool(forKey: PersistenceController.iCloudSyncEnabledKey)

        do {
            if syncEnabled {
                let cloudResult = try? cloudKeychain.set(token, key: key)
                let localResult = try? localKeychain.set(token, key: key)

                if cloudResult == nil && localResult == nil {
                    throw TokenError.setFailed
                }
            } else {
                try localKeychain.set(token, key: key)
            }
        } catch {
            throw TokenError.setFailed
        }
    }

    static func getToken(for service: String, identifier: String? = nil) throws -> String? {
        let key = makeKey(for: service, identifier: identifier)
        let syncEnabled = UserDefaults.standard.bool(forKey: PersistenceController.iCloudSyncEnabledKey)

        do {
            if syncEnabled {
                // Prefer iCloud
                if let token = try cloudKeychain.get(key, ignoringAttributeSynchronizable: false) {
                    return token
                }
                // Fallback to local copy, then normalize into iCloud
                if let token = try localKeychain.get(key, ignoringAttributeSynchronizable: false) {
                    try? cloudKeychain.set(token, key: key)
                    return token
                }
            } else {
                if let token = try localKeychain.get(key, ignoringAttributeSynchronizable: false) {
                    return token
                }
                if let token = try cloudKeychain.get(key, ignoringAttributeSynchronizable: false) {
                    try? localKeychain.set(token, key: key)
                    return token
                }
            }
            return nil
        } catch {
            throw TokenError.getFailed
        }
    }

    static func deleteToken(for service: String, identifier: String? = nil) throws {
        let key = makeKey(for: service, identifier: identifier)
        do {
            try localKeychain.remove(key)
            try cloudKeychain.remove(key)
        } catch {
            throw TokenError.deleteFailed
        }
    }

    /// Migrate existing tokens when sync setting changes
    /// Call this after changing iCloud sync setting and before app restart
    static func migrateTokensForSyncChange(toSyncEnabled: Bool) {
        let source = toSyncEnabled ? localKeychain : cloudKeychain
        let destination = toSyncEnabled ? cloudKeychain : localKeychain

        // Pull everything we see from the source store—do not rely on the
        // synchronizable flag because KeychainAccess can surface it in
        // different representations across macOS versions.
        guard let allItems = try? source.allItems() else { return }

        for item in allItems {
            guard let key = item["key"] as? String,
                  key.hasPrefix(tokenPrefix) else { continue }

            guard let token = try? source.get(key, ignoringAttributeSynchronizable: false) else { continue }

            // Copy token into the destination store. If the write fails, keep the source copy intact.
            _ = try? destination.set(token, key: key)
            // Never delete the source during migration; keeping both copies prevents
            // data loss if one keychain is temporarily unavailable.
        }
    }

    /// Ensure tokens live in the correct store based on the current sync setting.
    static func reconcileTokensWithCurrentSyncSetting() {
        let syncEnabled = UserDefaults.standard.bool(forKey: PersistenceController.iCloudSyncEnabledKey)
        migrateTokensForSyncChange(toSyncEnabled: syncEnabled)
    }

    // MARK: - Helpers

    private static func makeKey(for service: String, identifier: String?) -> String {
        if let identifier = identifier {
            return "\(tokenPrefix)\(service)_\(identifier)"
        } else {
            return "\(tokenPrefix)\(service)"
        }
    }
}
