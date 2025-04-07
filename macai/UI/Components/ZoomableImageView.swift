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
    }

    private func saveImage() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png, .jpeg]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = "image"
        savePanel.title = "Save Image"
        savePanel.message = "Choose where to save the image"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                guard let tiffData = image.tiffRepresentation,
                    let bitmap = NSBitmapImageRep(data: tiffData),
                    let imageData = bitmap.representation(using: .png, properties: [:])
                else {
                    print("Failed to convert image to data")
                    return
                }

                do {
                    try imageData.write(to: url)
                    print("Image saved successfully to \(url.path)")
                }
                catch {
                    print("Failed to save image: \(error)")
                }
            }
        }
    }
}
