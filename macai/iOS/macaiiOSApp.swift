//
//  macaiiOSApp.swift
//  macai
//
//  Minimal iOS entry point to keep the project compiling.
//

import SwiftUI

#if os(iOS)

@main
struct macaiiOSApp: App {
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)
    private let persistenceController = PersistenceController.shared

    init() {
        ValueTransformer.setValueTransformer(
            RequestMessagesTransformer(),
            forName: RequestMessagesTransformer.name
        )

        NotificationPresenter.shared.configure()
        NotificationPresenter.shared.onAuthorizationGranted = {
            DatabasePatcher.deliverPendingGeminiMigrationNotificationIfNeeded()
        }
        NotificationPresenter.shared.requestAuthorizationIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            IOSRootView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(store)
        }
    }
}

#endif
