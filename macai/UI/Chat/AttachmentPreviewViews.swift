//
//  AttachmentPreviewViews.swift
//  macai
//
//  Created by Codex on 2026-01-10
//

import CoreData
import PDFKit
import SwiftUI

struct ImageAttachmentTileView: View {
    let image: NSImage
    let size: CGFloat
    let onPreview: () -> Void

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(borderColor, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture {
                onPreview()
            }
    }

    private var borderColor: Color {
        Color.primary.opacity(0.12)
    }
}

struct PDFAttachmentTileView: View {
    let fileInfo: FileAttachmentInfo
    let size: CGFloat
    let onPreview: () -> Void

    @StateObject private var loader: PDFPreviewLoader
    @Environment(\.colorScheme) private var colorScheme

    init(fileInfo: FileAttachmentInfo, size: CGFloat, onPreview: @escaping () -> Void) {
        self.fileInfo = fileInfo
        self.size = size
        self.onPreview = onPreview
        _loader = StateObject(wrappedValue: PDFPreviewLoader(fileInfo: fileInfo))
    }

    var body: some View {
        let displayName = fileInfo.filename.isEmpty ? "Document.pdf" : fileInfo.filename

        Button(action: {
            onPreview()
        }) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.12))
                    .frame(width: size, height: size)

                if let thumbnail = loader.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                } else {
                    VStack(spacing: 6) {
                        if loader.isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Text(loader.previewUnavailable ? "Preview unavailable" : "PDF")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(secondaryTextColor)
                        }
                    }
                    .frame(width: size, height: size)
                }

                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask(
                        LinearGradient(
                            colors: [.clear, .black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .opacity(0.85)
                    )
                    .frame(height: size * 0.38)
                    .frame(maxWidth: size)

                Text(displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(primaryTextColor)
                    .shadow(color: shadowColor, radius: 1, x: 0, y: 1)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                    .frame(maxWidth: size - 16, alignment: .leading)

                if loader.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .padding(8)
                        .frame(maxWidth: size, maxHeight: size, alignment: .topTrailing)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loader.loadIfNeeded()
        }
    }

    private var gradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color.black.opacity(0.0),
                Color.black.opacity(0.6),
                Color.black.opacity(0.85),
            ]
        }
        return [
            Color.white.opacity(0.0),
            Color.white.opacity(0.7),
            Color.white.opacity(0.92),
        ]
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.85) : .black.opacity(0.65)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.55) : .white.opacity(0.6)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }
}

final class PDFPreviewLoader: ObservableObject {
    @Published var thumbnail: NSImage?
    @Published var previewURL: URL?
    @Published var isLoading = false
    @Published var previewUnavailable = false

    private let fileInfo: FileAttachmentInfo
    private static let imageCache = NSCache<NSUUID, NSImage>()
    private var isPreparingPreview = false

    init(fileInfo: FileAttachmentInfo) {
        self.fileInfo = fileInfo
        let key = fileInfo.id as NSUUID
        if let cachedImage = Self.imageCache.object(forKey: key) {
            self.thumbnail = cachedImage
        }
        if let cachedURL = PreviewFileHelper.cachedPreviewURL(for: fileInfo.id) {
            self.previewURL = cachedURL
        }
    }

    func loadIfNeeded() {
        if thumbnail == nil || previewURL == nil {
            prepareAssets(openWhenReady: false)
        }
    }

    private func prepareAssets(openWhenReady: Bool) {
        guard !isPreparingPreview else { return }
        isPreparingPreview = true
        isLoading = true

        PersistenceController.shared.container.performBackgroundTask { [weak self] context in
            guard let self else { return }
            let fetchRequest: NSFetchRequest<DocumentEntity> = DocumentEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", self.fileInfo.id as CVarArg)
            fetchRequest.fetchLimit = 1

            guard let documentEntity = try? context.fetch(fetchRequest).first,
                  let data = documentEntity.fileData else {
                DispatchQueue.main.async {
                    self.isPreparingPreview = false
                    self.isLoading = false
                }
                return
            }

            let key = self.fileInfo.id as NSUUID

            if self.thumbnail == nil {
                if let document = PDFDocument(data: data), let page = document.page(at: 0) {
                    let targetSize = NSSize(width: 400, height: 520)
                    let image = page.thumbnail(of: targetSize, for: .mediaBox)
                    Self.imageCache.setObject(image, forKey: key)
                    DispatchQueue.main.async {
                        self.thumbnail = image
                        self.previewUnavailable = false
                    }
                } else {
                    DispatchQueue.main.async {
                        self.previewUnavailable = true
                    }
                }
            }

            var generatedURL: URL?
            if self.previewURL == nil {
                let suggestedName = self.fileInfo.filename.isEmpty ? "Document.pdf" : self.fileInfo.filename
                let baseName = URL(fileURLWithPath: suggestedName).deletingPathExtension().lastPathComponent
                let name = "\(baseName).pdf"
                if let url = PreviewFileHelper.previewURL(
                    for: self.fileInfo.id,
                    data: data,
                    filename: name,
                    defaultExtension: "pdf"
                ) {
                    generatedURL = url
                }
            }

            DispatchQueue.main.async {
                self.isPreparingPreview = false
                self.isLoading = false
                if let generatedURL {
                    self.previewURL = generatedURL
                }
                if openWhenReady, let url = self.previewURL {
                    QuickLookPreviewer.shared.preview(url: url)
                }
            }
        }
    }
}
