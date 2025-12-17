//
//  ImageAttachment.swift
//  macai
//
//  Created by Renat on 03.04.2025
//

import CoreData
import Foundation
import SwiftUI
import UniformTypeIdentifiers

class ImageAttachment: Identifiable, ObservableObject {
    var id: UUID = UUID()
    var url: URL?
    @Published var image: NSImage?
    @Published var thumbnail: NSImage?
    @Published var isLoading: Bool = false
    @Published var error: Error?

    internal var imageEntity: ImageEntity?
    private var managedObjectContext: NSManagedObjectContext?
    private(set) var originalFileType: UTType
    private(set) var convertedToJPEG: Bool = false

    init(url: URL, context: NSManagedObjectContext? = nil) {
        self.url = url
        self.originalFileType = url.getUTType() ?? .jpeg
        self.managedObjectContext = context
        self.loadImage()
    }

    init(imageEntity: ImageEntity) {
        self.imageEntity = imageEntity
        self.id = imageEntity.id ?? UUID()

        if let formatString = imageEntity.imageFormat, !formatString.isEmpty {
            self.originalFileType = UTType(filenameExtension: formatString) ?? .jpeg
        }
        else {
            self.originalFileType = .jpeg
        }

        self.loadFromEntity()
    }

    init(image: NSImage, id: UUID = UUID()) {
        self.id = id
        self.image = image
        self.originalFileType = .jpeg
        self.createThumbnail(from: image)
    }

    private func loadImage() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let url = self.url else { return }

            do {
                if self.originalFileType == .heic || self.originalFileType == .heif {
                    if let convertedImage = self.convertHEICToJPEG() {
                        self.createThumbnail(from: convertedImage)
                        self.saveToEntity(image: convertedImage)

                        DispatchQueue.main.async {
                            self.image = convertedImage
                            self.convertedToJPEG = true
                            self.isLoading = false
                        }
                        return
                    }
                }

                if let image = NSImage(contentsOf: url) {
                    self.createThumbnail(from: image)
                    self.saveToEntity(image: image)

                    DispatchQueue.main.async {
                        self.image = image
                        self.isLoading = false
                    }
                }
                else {
                    throw NSError(
                        domain: "ImageAttachment",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to load image"]
                    )
                }
            }
            catch {
                DispatchQueue.main.async {
                    self.error = error
                    self.isLoading = false
                }
            }
        }
    }

    private func loadFromEntity() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let imageEntity = self.imageEntity else { return }

            if let imageData = imageEntity.image, let thumbnailData = imageEntity.thumbnail {
                let fullImage = NSImage(data: imageData)
                let thumbnailImage = NSImage(data: thumbnailData)

                DispatchQueue.main.async {
                    self.image = fullImage
                    self.thumbnail = thumbnailImage
                    self.isLoading = false
                }
            }
            else {
                DispatchQueue.main.async {
                    self.error = NSError(
                        domain: "ImageAttachment",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to load image from database"]
                    )
                    self.isLoading = false
                }
            }
        }
    }

    func saveToEntity(
        image: NSImage? = nil,
        context: NSManagedObjectContext? = nil,
        waitForCompletion: Bool = false
    ) {
        guard let contextToUse = context ?? managedObjectContext else { return }

        if context != nil {
            self.managedObjectContext = context
        }

        let persist: (ImagePersistencePayload) -> Void = { [weak self] payload in
            guard let self = self else { return }
            guard !payload.imageData.isEmpty else { return }

            contextToUse.performAndWait {
                if self.imageEntity == nil {
                    let newEntity = ImageEntity(context: contextToUse)
                    newEntity.id = self.id
                    self.imageEntity = newEntity
                }

                self.imageEntity?.imageFormat = payload.format
                self.imageEntity?.image = payload.imageData

                if let thumbnailData = payload.thumbnailData {
                    self.imageEntity?.thumbnail = thumbnailData
                }

                contextToUse.saveWithRetry(attempts: 1)
            }

            if self.image == nil {
                if Thread.isMainThread {
                    if self.image == nil {
                        self.image = payload.image
                    }
                }
                else {
                    DispatchQueue.main.async {
                        if self.image == nil {
                            self.image = payload.image
                        }
                    }
                }
            }

            if let thumbnailImage = payload.thumbnailImage {
                let updateThumbnail = {
                    if self.thumbnail == nil {
                        self.thumbnail = thumbnailImage
                    }
                }

                if Thread.isMainThread {
                    updateThumbnail()
                }
                else {
                    DispatchQueue.main.async(execute: updateThumbnail)
                }
            }
        }

        if waitForCompletion {
            guard let payload = preparePersistencePayload(using: image) else { return }
            persist(payload)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let payload = self.preparePersistencePayload(using: image) else { return }
            persist(payload)
        }
    }

    private func createThumbnail(from image: NSImage) {
        guard let thumbnail = generateThumbnailImage(from: image) else { return }

        DispatchQueue.main.async {
            self.thumbnail = thumbnail
        }
    }

    private func generateThumbnailImage(from image: NSImage) -> NSImage? {
        let thumbnailSize: CGFloat = AppConstants.thumbnailSize

        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        let aspectRatio = size.width / size.height

        var newWidth: CGFloat
        var newHeight: CGFloat

        if size.width > size.height {
            newWidth = thumbnailSize
            newHeight = thumbnailSize / aspectRatio
        }
        else {
            newHeight = thumbnailSize
            newWidth = thumbnailSize * aspectRatio
        }

        let thumbnailImage = NSImage(size: NSSize(width: newWidth, height: newHeight))

        thumbnailImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: newWidth, height: newHeight),
            from: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            operation: .copy,
            fraction: 1.0
        )
        thumbnailImage.unlockFocus()

        return thumbnailImage
    }

    private func convertHEICToJPEG() -> NSImage? {
        guard let url = self.url else { return nil }
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { return nil }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [:]) else { return nil }

        return NSImage(data: jpegData)
    }

    func toBase64() -> String? {
        guard let image = self.image else { return nil }

        let resizedImage = resizeImageIfNeeded(image)

        guard let tiffData = resizedImage.tiffRepresentation,
            let bitmapImage = NSBitmapImageRep(data: tiffData),
            let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        else {
            return nil
        }

        return jpegData.base64EncodedString()
    }

    private func resizeImageIfNeeded(_ image: NSImage) -> NSImage {
        let maxShortSide: CGFloat = 768
        let maxLongSide: CGFloat = 2000

        let size = image.size
        let shortSide = min(size.width, size.height)
        let longSide = max(size.width, size.height)

        if shortSide <= maxShortSide && longSide <= maxLongSide {
            return image
        }

        var newWidth: CGFloat
        var newHeight: CGFloat

        if size.width < size.height {
            newWidth = maxShortSide
            newHeight = min(maxLongSide, size.height * (maxShortSide / size.width))
        }
        else {
            newHeight = maxShortSide
            newWidth = min(maxLongSide, size.width * (maxShortSide / size.height))
        }

        let newImage = NSImage(size: NSSize(width: newWidth, height: newHeight))

        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: newWidth, height: newHeight),
            from: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()

        return newImage
    }

    private func getFormatString(from type: UTType) -> String {
        switch type {
        case .jpeg:
            return "jpeg"
        case .png:
            return "png"
        default:
            // Try to get the preferred filename extension
            return type.preferredFilenameExtension ?? "jpeg"
        }
    }

    private func getImageData(from bitmapImage: NSBitmapImageRep, using type: UTType) -> Data? {
        switch type {
        case .png:
            return bitmapImage.representation(using: .png, properties: [:])
        case .jpeg:
            return bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        default:
            // For all other types (HEIC/HEIF/WEBP/unknown), prefer JPEG to keep size modest.
            return bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        }
    }

    /// Progressively compress image to fit within CloudKit size limits
    /// Optimized with iteration limits to prevent excessive encoding passes
    private func compressForCloudKit(image: NSImage, currentData: Data, targetSize: Int) -> Data {
        var compressionFactor: CGFloat = 0.7
        var resizedImage = image
        var resultData = currentData
        
        // Maximum iterations to prevent runaway loops
        let maxCompressionIterations = 7
        let maxResizeIterations = 10
        var compressionIterations = 0

        // First, try reducing compression quality
        while resultData.count > targetSize && compressionFactor > 0.1 && compressionIterations < maxCompressionIterations {
            compressionIterations += 1
            
            if let tiffData = resizedImage.tiffRepresentation,
               let bitmapImage = NSBitmapImageRep(data: tiffData),
               let compressedData = bitmapImage.representation(
                   using: .jpeg,
                   properties: [.compressionFactor: compressionFactor]
               ) {
                resultData = compressedData
                
                // Early exit if we've reached the target
                if resultData.count <= targetSize {
                    break
                }
            }
            compressionFactor -= 0.1
        }

        // If still too large, reduce image dimensions
        if resultData.count > targetSize {
            let scaleFactor: CGFloat = 0.75
            var currentSize = resizedImage.size
            var resizeIterations = 0

            while resultData.count > targetSize && currentSize.width > 200 && resizeIterations < maxResizeIterations {
                resizeIterations += 1
                
                currentSize = NSSize(
                    width: currentSize.width * scaleFactor,
                    height: currentSize.height * scaleFactor
                )

                let scaledImage = NSImage(size: currentSize)
                scaledImage.lockFocus()
                NSGraphicsContext.current?.imageInterpolation = .high
                resizedImage.draw(
                    in: NSRect(origin: .zero, size: currentSize),
                    from: NSRect(origin: .zero, size: resizedImage.size),
                    operation: .copy,
                    fraction: 1.0
                )
                scaledImage.unlockFocus()

                resizedImage = scaledImage

                if let tiffData = resizedImage.tiffRepresentation,
                   let bitmapImage = NSBitmapImageRep(data: tiffData),
                   let compressedData = bitmapImage.representation(
                       using: .jpeg,
                       properties: [.compressionFactor: 0.6]
                   ) {
                    resultData = compressedData
                    
                    // Early exit if we've reached the target
                    if resultData.count <= targetSize {
                        break
                    }
                }
            }
        }

        return resultData
    }
}

extension ImageAttachment {
    private struct ImagePersistencePayload {
        let image: NSImage
        let imageData: Data
        let format: String
        let thumbnailData: Data?
        let thumbnailImage: NSImage?
    }

    private func preparePersistencePayload(using providedImage: NSImage?) -> ImagePersistencePayload? {
        var workingImage = providedImage ?? self.image

        if workingImage == nil {
            if (originalFileType == .heic || originalFileType == .heif),
                let converted = convertHEICToJPEG()
            {
                workingImage = converted
                convertedToJPEG = true
            }
            else if let url = self.url {
                workingImage = NSImage(contentsOf: url)
            }
        }

        guard let imageToPersist = workingImage,
            let tiffData = imageToPersist.tiffRepresentation,
            let bitmapImage = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }

        // Use PNG only when the original is PNG; otherwise force JPEG to avoid ballooning size.
        let usePNG = (originalFileType == .png)
        var targetFormat = usePNG ? "png" : "jpeg"
        var imageData: Data?

        if usePNG {
            imageData = bitmapImage.representation(using: .png, properties: [:])
        } else {
            imageData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
            if originalFileType != .jpeg {
                convertedToJPEG = true
            }
        }

        if imageData == nil,
           let jpegFallback = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        {
            imageData = jpegFallback
            targetFormat = "jpeg"
        }

        guard var finalImageData = imageData else {
            return nil
        }

        // Avoid creating empty CKAssets; bail out if we somehow got zero bytes.
        guard finalImageData.count > 0 else { return nil }

        // CloudKit stores binary data as CKAsset. Apple recommends keeping assets under ~250 MB for performance.
        // Use a safety margin to avoid slow transfers or CKError.limitExceeded.
        let cloudKitLimit = 250_000_000 // 250 MB safety threshold for CKAsset payloads
        if finalImageData.count > cloudKitLimit {
            finalImageData = compressForCloudKit(
                image: imageToPersist,
                currentData: finalImageData,
                targetSize: cloudKitLimit
            )

            // If still too large, fail the save so caller can handle/retry with a smaller image.
            guard finalImageData.count <= cloudKitLimit else { return nil }
        }

        let thumbnailImage = self.thumbnail ?? generateThumbnailImage(from: imageToPersist)
        var thumbnailData: Data?

        if let thumbnailImage,
           let thumbnailTiff = thumbnailImage.tiffRepresentation,
           let thumbnailBitmap = NSBitmapImageRep(data: thumbnailTiff)
        {
            thumbnailData = thumbnailBitmap.representation(
                using: .jpeg,
                properties: [.compressionFactor: 0.7]
            )
            if let data = thumbnailData, data.isEmpty {
                thumbnailData = nil
            }
        }

        return ImagePersistencePayload(
            image: imageToPersist,
            imageData: finalImageData,
            format: targetFormat,
            thumbnailData: thumbnailData,
            thumbnailImage: thumbnailImage
        )
    }
}

extension URL {
    func getUTType() -> UTType? {
        let fileExtension = self.pathExtension.lowercased()

        switch fileExtension {
        case "jpg", "jpeg":
            return .jpeg
        case "png":
            return .png
        case "webp":
            return .webP
        case "heic":
            return .heic
        case "heif":
            return .heif
        default:
            return UTType(filenameExtension: fileExtension)
        }
    }
}
