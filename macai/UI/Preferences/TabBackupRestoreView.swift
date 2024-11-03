//
//  TabBackupRestoreView.swift
//  macai
//
//  Created by Renat Notfullin on 11.11.2023.
//

import SwiftUI

struct BackupRestoreView: View {
    @ObservedObject var store: ChatStore

    var body: some View {
        VStack {
            HStack {
                Text("Backup & Restore")
                    .font(.headline)
                Spacer()
            }

            HStack {
                Text("Chats are exported into plaintext, unencrypted JSON file. You can import them back later.")
                    .foregroundColor(.gray)
                Spacer()
            }
            .padding(.bottom, 16)

            HStack {
                Text("Export chats history")
                Spacer()
                Button("Export to file...") {

                    store.loadFromCoreData { result in
                        switch result {
                        case .failure(let error):
                            fatalError(error.localizedDescription)
                        case .success(let chats):
                            let encoder = JSONEncoder()
                            encoder.outputFormatting = .prettyPrinted
                            let data = try! encoder.encode(chats)
                            let savePanel = NSSavePanel()
                            savePanel.allowedContentTypes = [.json]
                            savePanel.nameFieldStringValue = "chats.json"
                            savePanel.begin { (result) in
                                if result == .OK {
                                    do {
                                        try data.write(to: savePanel.url!)
                                    }
                                    catch {
                                        print(error)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            HStack {
                Text("Import chats history")
                Spacer()
                Button("Import from file...") {
                    let openPanel = NSOpenPanel()
                    openPanel.allowedContentTypes = [.json]
                    openPanel.begin { (result) in
                        if result == .OK {
                            do {
                                let data = try Data(contentsOf: openPanel.url!)
                                let decoder = JSONDecoder()
                                let chats = try decoder.decode([Chat].self, from: data)

                                store.saveToCoreData(chats: chats) { result in
                                    print("State saved")
                                    if case .failure(let error) = result {
                                        fatalError(error.localizedDescription)
                                    }
                                }

                            }
                            catch {
                                print(error)
                            }
                        }
                    }
                }
            }
        }
        .padding(32)
    }

}
