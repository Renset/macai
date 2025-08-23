//
//  Extensions.swift
//  macai
//
//  Created by Renat on 08.06.2024.
//

import CommonCrypto
import CoreData
import Foundation
import SwiftUI

extension Data {
    public func sha256() -> String {
        return hexStringFromData(input: digest(input: self as NSData))
    }

    private func digest(input: NSData) -> NSData {
        let digestLength = Int(CC_SHA256_DIGEST_LENGTH)
        var hash = [UInt8](repeating: 0, count: digestLength)
        CC_SHA256(input.bytes, UInt32(input.length), &hash)
        return NSData(bytes: hash, length: digestLength)
    }

    private func hexStringFromData(input: NSData) -> String {
        var bytes = [UInt8](repeating: 0, count: input.length)
        input.getBytes(&bytes, length: input.length)

        var hexString = ""
        for byte in bytes {
            hexString += String(format: "%02x", UInt8(byte))
        }

        return hexString
    }
}

extension String {
    public func sha256() -> String {
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
        }
        catch {
            print("Core Data save failed: \(error)")

            self.rollback()

            if attempts > 0 {
                print("Retrying save operation...")
                self.saveWithRetry(attempts: attempts - 1)
            }
            else {
                print("Failed to save after multiple attempts")
            }
        }
    }
}

extension View {
    func border(width: CGFloat, edges: [Edge], color: Color) -> some View {
        overlay(EdgeBorder(width: width, edges: edges).foregroundColor(color))
    }
}

struct EdgeBorder: Shape {
    var width: CGFloat
    var edges: [Edge]

    func path(in rect: CGRect) -> Path {
        edges.map { edge -> Path in
            switch edge {
            case .top: return Path(.init(x: rect.minX, y: rect.minY, width: rect.width, height: width))
            case .bottom: return Path(.init(x: rect.minX, y: rect.maxY - width, width: rect.width, height: width))
            case .leading: return Path(.init(x: rect.minX, y: rect.minY, width: width, height: rect.height))
            case .trailing: return Path(.init(x: rect.maxX - width, y: rect.minY, width: width, height: rect.height))
            }
        }.reduce(into: Path()) { $0.addPath($1) }
    }
}

extension Binding {
    func equalTo<A: Equatable>(_ value: A) -> Binding<Bool> where Value == A? {
        Binding<Bool> {
            wrappedValue == value
        } set: {
            if $0 {
                wrappedValue = value
            }
            else if wrappedValue == value {
                wrappedValue = nil
            }
        }
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        self.init(
            red: Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgb & 0x0000FF) / 255.0
        )
    }

    func toHex() -> String {
        let components = self.cgColor?.components
        let r: CGFloat = components?[0] ?? 0.0
        let g: CGFloat = components?[1] ?? 0.0
        let b: CGFloat = components?[2] ?? 0.0

        let hexString = String.init(
            format: "#%02lX%02lX%02lX",
            lroundf(Float(r * 255)),
            lroundf(Float(g * 255)),
            lroundf(Float(b * 255))
        )

        return hexString
    }

}

extension Double {
    func toInt16() -> Int16? {
        guard self >= Double(Int16.min) && self <= Double(Int16.max) else {
            return nil
        }
        return Int16(self)
    }
}

extension Int16 {
    var toDouble: Double {
        return Double(self)
    }
}

extension Float {
    func roundedToOneDecimal() -> Float {
        return (self * 10).rounded() / 10
    }
}

extension PersistenceController {
    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext

        let chat = ChatEntity(context: viewContext)
        chat.id = UUID()
        chat.name = "Sample Chat"
        chat.createdDate = Date()
        chat.updatedDate = Date()
        chat.systemMessage = AppConstants.chatGptSystemMessage
        chat.gptModel = AppConstants.chatGptDefaultModel

        let persona = PersonaEntity(context: viewContext)
        persona.name = "Assistant"
        persona.color = "#FF0000"
        chat.persona = persona

        try? viewContext.save()
        return result
    }()
}

extension Range where Bound == String.Index {
    func toNSRange(in string: String) -> NSRange? {
        return NSRange(self, in: string)
    }
}
