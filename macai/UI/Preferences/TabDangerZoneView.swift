//
//  TabDangerZoneView.swift
//  macai
//
//  Created by Renat Notfullin on 11.11.2023.
//

import SwiftUI

struct DangerZoneView: View {
    @ObservedObject var store: ChatStore
    @State private var currentAlert: AlertType?
        
    enum AlertType: Identifiable {
        case deleteChats, deletePersonas
        var id: Self { self }
    }

    var body: some View {
        VStack {
            HStack {
                Text("Danger Zone")
                    .font(.headline)
                Spacer()
            }

            HStack {
                Text("This action is irreversible. All your chats will be deleted from the database. It's recommended to make an export of your chats before deleting them.")
                    .foregroundColor(.gray)
                Spacer()
            }
            .padding(.bottom, 16)
            
            VStack() {
                Button(action: {
                    currentAlert = .deleteChats
                }, label: {
                    Label("Delete all chats", systemImage: "trash").foregroundColor(.red)
                })
                Button(action: {
                    currentAlert = .deletePersonas
                }) {
                    Label("Delete all AI Personas", systemImage: "trash").foregroundColor(.red)
                }
            }
            
        }
        .padding(32)
        .alert(item: $currentAlert) { alertType in
            switch alertType {
            case .deleteChats:
                return Alert(
                    title: Text("Delete All Chats"),
                    message: Text("Are you sure you want to delete all chats? This action cannot be undone."),
                    primaryButton: .destructive(Text("Delete")) {
                        store.deleteAllChats()
                    },
                    secondaryButton: .cancel()
                )
            case .deletePersonas:
                return Alert(
                    title: Text("Delete All AI Personas"),
                    message: Text("Are you sure you want to delete all AI personas?"),
                    primaryButton: .destructive(Text("Delete all personas")) {
                        store.deleteAllPersonas()
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }
}
