//
//  RequestMessagesTransformer.swift
//  macai
//
//  Created by Renat on 10.11.2024.
//

import Foundation

@objc(RequestMessagesTransformer)
class RequestMessagesTransformer: NSSecureUnarchiveFromDataTransformer {

    static let name = NSValueTransformerName(rawValue: "RequestMessagesTransformer")

    override class func transformedValueClass() -> AnyClass {
        return NSArray.self
    }

    override class func allowsReverseTransformation() -> Bool {
        return true
    }

    override func transformedValue(_ value: Any?) -> Any? {
        guard let messages = value as? [[String: String]] else {
            return nil
        }
        return try? NSKeyedArchiver.archivedData(withRootObject: messages, requiringSecureCoding: true)
    }

    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else {
            return nil
        }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSArray.self, from: data) as? [[String: String]]
    }
}
