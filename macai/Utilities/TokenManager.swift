//
//  TokenManager.swift
//  macai
//
//  Created by Renat Notfullin on 03.09.2024.
//

import Foundation
import KeychainAccess

class TokenManager {
    private static let keychain = Keychain(service: "notfullin.com.macai")
    private static let tokenPrefix = "api_token_"
    
    enum TokenError: Error {
        case setFailed
        case getFailed
        case deleteFailed
    }
    
    static func setToken(_ token: String, for service: String, identifier: String? = nil) throws {
        let key = makeKey(for: service, identifier: identifier)
        do {
            try keychain.set(token, key: key)
        } catch {
            throw TokenError.setFailed
        }
    }
    
    static func getToken(for service: String, identifier: String? = nil) throws -> String? {
        let key = makeKey(for: service, identifier: identifier)
        do {
            guard let token = try keychain.get(key) else {
                throw TokenError.getFailed
            }
            return token
        } catch {
            throw TokenError.getFailed
        }
    }
    
    static func deleteToken(for service: String, identifier: String? = nil) throws {
        let key = makeKey(for: service, identifier: identifier)
        do {
            try keychain.remove(key)
        } catch {
            throw TokenError.deleteFailed
        }
    }
    
    private static func makeKey(for service: String, identifier: String?) -> String {
        if let identifier = identifier {
            return "\(tokenPrefix)\(service)_\(identifier)"
        } else {
            return "\(tokenPrefix)\(service)"
        }
    }
}
