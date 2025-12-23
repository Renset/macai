//
//  ChatAttentionStore.swift
//  macai
//
//  Created by Renat Notfullin on 23.12.2025
//

import AppKit
import Foundation

final class ChatAttentionStore: ObservableObject {
    static let shared = ChatAttentionStore()

    @Published private(set) var chatIds: Set<UUID> = []

    private let storageKey = "ChatAttentionStore.chatIds"

    private init() {
        load()
    }

    func mark(_ chatId: UUID) {
        guard !chatIds.contains(chatId) else { return }
        chatIds.insert(chatId)
        persist()
        updateDockBadge()
    }

    func clear(_ chatId: UUID) {
        guard chatIds.contains(chatId) else { return }
        chatIds.remove(chatId)
        persist()
        updateDockBadge()
    }

    func contains(_ chatId: UUID) -> Bool {
        chatIds.contains(chatId)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let ids = try? JSONDecoder().decode([UUID].self, from: data)
        else {
            return
        }
        chatIds = Set(ids)
        updateDockBadge()
    }

    private func persist() {
        let ids = Array(chatIds)
        if let data = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func updateDockBadge() {
        let count = chatIds.count
        let badge = count > 0 ? "\(count)" : nil
        print("Setting dock badge count: \(count)")

        if Thread.isMainThread {
            NSApplication.shared.dockTile.showsApplicationBadge = true
            NSApplication.shared.dockTile.badgeLabel = badge
            NSApplication.shared.dockTile.display()
            print("Dock badge label now: \(NSApplication.shared.dockTile.badgeLabel ?? "nil")")
        }
        else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updateDockBadge()
            }
        }
    }
}
