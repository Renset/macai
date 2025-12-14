//
//  ZoomableImageView.swift
//  macai
//
//  Created by Renat on 03.04.2025
//

import SwiftUI

struct ZoomableImageView: View {
    let image: NSImage
    let imageAspectRatio: CGFloat
    let chatName: String?
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geometry in
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .clipped()
                    .padding(0)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                scale *= delta
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                            }
                    )
                    .gesture(
                        TapGesture(count: 2)
                            .onEnded {
                                withAnimation {
                                    scale = scale > 1.0 ? 1.0 : 2.0
                                    if scale == 1.0 {
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                }
                            }
                    )
            }

            Group {
                HStack {
                    Button(action: {
                        withAnimation {
                            scale = min(scale + 0.25, 5.0)
                        }
                    }) {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .keyboardShortcut("=", modifiers: [])
                    .keyboardShortcut("+", modifiers: [])

                    Button(action: {
                        withAnimation {
                            scale = max(scale - 0.25, 0.25)
                        }
                    }) {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .keyboardShortcut("-", modifiers: [])

                    Button(action: {
                        withAnimation {
                            scale = 1.0
                            offset = .zero
                        }
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                    }

                    Button(action: {
                        saveImage()
                    }) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .keyboardShortcut("s", modifiers: .command)

                    Spacer()
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                    }
                    .keyboardShortcut("q", modifiers: .command)
                }
                .padding(8)
            }
            .background(.ultraThinMaterial)
            .cornerRadius(10)
            .padding(10)
        }
        .aspectRatio(imageAspectRatio, contentMode: .fill)
        .padding(0)
        .frame(minWidth: imageAspectRatio > 1.4 ? 800 : nil)
    }

    private func saveImage() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png, .jpeg]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = defaultFileName()
        savePanel.title = "Save Image"
        savePanel.message = "Choose where to save the image"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                let ext = url.pathExtension.lowercased()
                let isPNG = ext == "png"

                guard
                    let tiffData = image.tiffRepresentation,
                    let bitmap = NSBitmapImageRep(data: tiffData),
                    let imageData = isPNG
                        ? bitmap.representation(using: .png, properties: [:])
                        : bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
                else {
                    print("Failed to convert image to data")
                    return
                }

                do {
                    let destinationURL: URL
                    if url.pathExtension.isEmpty {
                        destinationURL = url.appendingPathExtension(isPNG ? "png" : "jpg")
                    } else {
                        destinationURL = url
                    }

                    try imageData.write(to: destinationURL)
                    print("Image saved successfully to \(url.path)")
                }
                catch {
                    print("Failed to save image: \(error)")
                }
            }
        }
    }

    private func defaultFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())

        if let name = chatName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            // APFS forbids only "/" and control chars; Finder also blocks ":".
            var sanitized = name
            sanitized.unicodeScalars.removeAll { scalar in
                CharacterSet(charactersIn: "/:").contains(scalar)
                || CharacterSet.controlCharacters.contains(scalar)
            }
            sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sanitized.isEmpty {
                return "\(sanitized)_\(timestamp).jpg"
            }
        }

        return "chat_image_\(timestamp).jpg"
    }
}
