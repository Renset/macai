//
//  ImageProcessing.swift
//  macai
//
//  Cross-platform image helpers for macOS and iOS.
//

import Foundation
import CoreGraphics

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum ImageProcessing {
    static func loadImage(from url: URL) -> NSImage? {
        #if os(macOS)
        return NSImage(contentsOf: url)
        #else
        guard let data = try? Data(contentsOf: url) else { return nil }
        return NSImage(data: data)
        #endif
    }

    static func jpegData(from image: NSImage, compression: CGFloat) -> Data? {
        #if os(macOS)
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        return bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: compression])
        #else
        return image.jpegData(compressionQuality: compression)
        #endif
    }

    static func pngData(from image: NSImage) -> Data? {
        #if os(macOS)
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        return bitmapImage.representation(using: .png, properties: [:])
        #else
        return image.pngData()
        #endif
    }

    static func resize(image: NSImage, to targetSize: CGSize) -> NSImage? {
        guard targetSize.width > 0, targetSize.height > 0 else { return nil }
        #if os(macOS)
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: CGRect(origin: .zero, size: targetSize),
            from: CGRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()
        return newImage
        #else
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        #endif
    }

    static func thumbnail(from image: NSImage, maxSize: CGFloat) -> NSImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        let aspectRatio = size.width / size.height
        var newWidth: CGFloat
        var newHeight: CGFloat

        if size.width > size.height {
            newWidth = maxSize
            newHeight = maxSize / aspectRatio
        } else {
            newHeight = maxSize
            newWidth = maxSize * aspectRatio
        }

        return resize(image: image, to: CGSize(width: newWidth, height: newHeight))
    }
}
