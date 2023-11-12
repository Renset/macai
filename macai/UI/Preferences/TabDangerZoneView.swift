//
//  TabDangerZoneView.swift
//  macai
//
//  Created by Renat Notfullin on 11.11.2023.
//

import SwiftUI

struct DangerZoneView: View {
    @ObservedObject var store: ChatStore

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
            
            HStack {
                Button(action: {
                    let alert = NSAlert()
                    alert.messageText = "Are you sure you want to delete all chats?"
                    alert.informativeText = "This action cannot be undone. It's recommended to make an export of your chats before deleting them."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Delete")
                    alert.addButton(withTitle: "Cancel")
                    alert.beginSheetModal(for: NSApp.mainWindow!) { (response) in
                        if response == .alertFirstButtonReturn {
                            store.deleteAllChats()
                        }
                    }
                }, label: {
                    Text("Delete all chats").foregroundColor(.red)
                })
                Spacer()
            }
        }
        .padding(32)
    }
}
