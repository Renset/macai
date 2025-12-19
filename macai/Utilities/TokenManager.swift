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

    /// Remove all synchronizable (iCloud) tokens for this app from the keychain.
    /// Local tokens are left intact so the user keeps access on the current device.
    static func clearCloudTokens() {
        _ = try? cloudKeychain.removeAll()
    }

    /// Cache all tokens into memory. Use this before any destructive keychain operations.
    /// Returns a dictionary mapping key names to token values.
    static func cacheAllTokens() -> [String: String] {
        var tokens: [String: String] = [:]

        // Read tokens from local keychain first (single pass - read values during enumeration)
        if let localKeys = try? localKeychain.allKeys() {
            for key in localKeys where key.hasPrefix(tokenPrefix) {
                if let token = try? localKeychain.get(key, ignoringAttributeSynchronizable: true) {
                    tokens[key] = token
                }
            }
        }

        // Read tokens from cloud keychain, overwriting local if cloud has a value
        // (cloud takes precedence)
        if let cloudKeys = try? cloudKeychain.allKeys() {
            for key in cloudKeys where key.hasPrefix(tokenPrefix) {
                if let token = try? cloudKeychain.get(key, ignoringAttributeSynchronizable: true) {
                    tokens[key] = token
                }
            }
        }

        return tokens
    }

    /// Restore cached tokens to local keychain.
    /// Call this after clearing cloud tokens to ensure tokens are available locally.
    static func restoreTokensToLocalKeychain(_ tokens: [String: String]) {
        for (key, token) in tokens {
            _ = try? localKeychain.set(token, key: key)
        }
    }

    /// Restore cached tokens to cloud keychain.
    /// Call this when enabling iCloud sync to ensure tokens are synced.
    static func restoreTokensToCloudKeychain(_ tokens: [String: String]) {
        for (key, token) in tokens {
            _ = try? cloudKeychain.set(token, key: key)
        }
    }

    /// Migrate existing tokens when sync setting changes
    /// Call this after changing iCloud sync setting and before app restart
    static func migrateTokensForSyncChange(toSyncEnabled: Bool) {
        let destination = toSyncEnabled ? cloudKeychain : localKeychain

        // First pass: migrate tokens from local keychain
        if let localKeys = try? localKeychain.allKeys() {
            for key in localKeys where key.hasPrefix(tokenPrefix) {
                if let token = try? localKeychain.get(key, ignoringAttributeSynchronizable: true) {
                    _ = try? destination.set(token, key: key)
                }
            }
        }

        // Second pass: migrate tokens from cloud keychain (only if not already migrated)
        // Cloud tokens take precedence, so overwrite any local values
        if let cloudKeys = try? cloudKeychain.allKeys() {
            for key in cloudKeys where key.hasPrefix(tokenPrefix) {
                if let token = try? cloudKeychain.get(key, ignoringAttributeSynchronizable: true) {
                    _ = try? destination.set(token, key: key)
                }
            }
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
