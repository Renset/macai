//
//  Extensions.swift
//  macai
//
//  Created by Renat on 08.06.2024.
//

import Foundation
import CommonCrypto
import CoreData

extension Data{
    public func sha256() -> String{
        return hexStringFromData(input: digest(input: self as NSData))
    }
    
    private func digest(input : NSData) -> NSData {
        let digestLength = Int(CC_SHA256_DIGEST_LENGTH)
        var hash = [UInt8](repeating: 0, count: digestLength)
        CC_SHA256(input.bytes, UInt32(input.length), &hash)
        return NSData(bytes: hash, length: digestLength)
    }
    
    private  func hexStringFromData(input: NSData) -> String {
        var bytes = [UInt8](repeating: 0, count: input.length)
        input.getBytes(&bytes, length: input.length)
        
        var hexString = ""
        for byte in bytes {
            hexString += String(format:"%02x", UInt8(byte))
        }
        
        return hexString
    }
}

public extension String {
    func sha256() -> String{
        if let stringData = self.data(using: String.Encoding.utf8) {
            return stringData.sha256()
        }
        return ""
    }
}

extension NSManagedObjectContext {
    func saveWithRetry(attempts: Int) {
        do {
            try self.save()
        } catch {
            print("Core Data save failed: \(error)")
            
            self.rollback()
            
            if attempts > 0 {
                print("Retrying save operation...")
                self.saveWithRetry(attempts: attempts - 1)
            } else {
                print("Failed to save after multiple attempts")
            }
        }
    }
}
