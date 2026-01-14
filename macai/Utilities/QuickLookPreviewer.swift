//
//  QuickLookPreviewer.swift
//  macai
//
//  Created by Renat Notfullin on 09.01.2026
//

import AppKit
#if canImport(QuickLookUI)
import QuickLookUI
#endif

final class QuickLookPreviewer: NSObject {
    static let shared = QuickLookPreviewer()

    struct PreviewItemRequest {
        let id: UUID
        let title: String?
        let url: URL?
        let load: ((@escaping (URL?) -> Void) -> Void)?

        init(id: UUID, title: String?, url: URL?) {
            self.id = id
            self.title = title
            self.url = url
            self.load = nil
        }

        init(id: UUID, title: String?, load: @escaping (@escaping (URL?) -> Void) -> Void) {
            self.id = id
            self.title = title
            self.url = nil
            self.load = load
        }
    }

    private final class PreviewItem: NSObject, QLPreviewItem {
        let id: UUID
        let title: String?
        private let load: ((@escaping (URL?) -> Void) -> Void)?
        private var isLoading = false

        @objc dynamic var previewItemURL: URL?
        @objc dynamic var previewItemTitle: String? { title }

        init(request: PreviewItemRequest) {
            self.id = request.id
            self.title = request.title
            self.previewItemURL = request.url
            self.load = request.load
        }

        func loadIfNeeded(qos: DispatchQoS.QoSClass, completion: @escaping () -> Void) {
            guard previewItemURL == nil else {
                completion()
                return
            }
            // If we are already loading, do nothing. Calling completion() here would trigger
            // a refresh panel loop because the URL is still nil.
            guard let load, !isLoading else {
                return
            }
            isLoading = true
            DispatchQueue.global(qos: qos).async { [weak self] in
                load { url in
                    DispatchQueue.main.async {
                        self?.previewItemURL = url
                        self?.isLoading = false
                        completion()
                    }
                }
            }
        }
    }

    private var previewItems: [PreviewItem] = []

    func preview(url: URL) {
        preview(urls: [url])
    }

    func preview(urls: [URL]) {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return }
        let requests = existing.map { url in
            PreviewItemRequest(id: UUID(), title: url.lastPathComponent, url: url)
        }
        preview(requests: requests, selectedIndex: 0)
    }

    func preview(requests: [PreviewItemRequest], selectedIndex: Int) {
        guard !requests.isEmpty else { return }
        previewItems = requests.map { PreviewItem(request: $0) }
        let clampedIndex = max(0, min(selectedIndex, previewItems.count - 1))

        DispatchQueue.main.async {
            #if canImport(QuickLookUI)
            if let panel = QLPreviewPanel.shared() {
                panel.dataSource = self
                panel.delegate = self
                panel.currentPreviewItemIndex = clampedIndex
                panel.makeKeyAndOrderFront(nil)
                panel.reloadData()
                panel.refreshCurrentPreviewItem()
                return
            }
            #endif
            if let url = self.previewItems[clampedIndex].previewItemURL ?? self.previewItems.first?.previewItemURL {
                NSWorkspace.shared.open(url)
            }
        }
        loadItem(at: clampedIndex, qos: .userInitiated)
    }

    func preview(image: NSImage, filename: String? = nil) {
        let trimmed = filename?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (trimmed?.isEmpty == false) ? trimmed! : "Image.jpg"
        let id = UUID()
        let request = PreviewItemRequest(id: id, title: name) { completion in
            guard let data = image.jpegData(compression: 0.9) else {
                completion(nil)
                return
            }
            let url = PreviewFileHelper.writeTemporaryFile(
                data: data,
                filename: name,
                defaultExtension: "jpg",
                id: id
            )
            completion(url)
        }
        preview(requests: [request], selectedIndex: 0)
    }

    private func loadItem(at index: Int, qos: DispatchQoS.QoSClass) {
        guard index >= 0, index < previewItems.count else { return }
        let item = previewItems[index]
        item.loadIfNeeded(qos: qos) { [weak self] in
            self?.refreshPanelIfVisible(for: index)
        }
    }

    private func refreshPanelIfVisible(for index: Int) {
        DispatchQueue.main.async {
            #if canImport(QuickLookUI)
            if let panel = QLPreviewPanel.shared(),
               panel.currentPreviewItemIndex == index {
                panel.refreshCurrentPreviewItem()
            }
            #endif
        }
    }
}

private extension NSImage {
    func jpegData(compression: CGFloat) -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }

        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: compression])
    }
}

#if canImport(QuickLookUI)
extension QuickLookPreviewer: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewItems.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem {
        let currentIndex = panel.currentPreviewItemIndex
        if abs(index - currentIndex) <= 1 {
            let qos: DispatchQoS.QoSClass = (index == currentIndex) ? .userInitiated : .utility
            loadItem(at: index, qos: qos)
        }
        return previewItems[index]
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        let currentIndex = panel.currentPreviewItemIndex
        switch event.keyCode {
        case 123: // left arrow
            loadItem(at: currentIndex - 1, qos: .utility)
            return false
        case 124: // right arrow
            loadItem(at: currentIndex + 1, qos: .utility)
            return false
        default:
            return false
        }
    }
}
#endif
