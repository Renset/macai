//
//  TabAPIServices.swift
//  macai
//
//  Created by Renat Notfullin on 13.09.2024.
//

import CoreData
import SwiftUI

struct TabAPIServicesView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>

    @State private var isShowingAddOrEditService = false
    @State private var selectedServiceID: NSManagedObjectID?
    @State private var refreshID = UUID()
    @AppStorage("defaultApiService") private var defaultApiServiceID: String?

    private var isSelectedServiceDefault: Bool {
        guard let selectedServiceID = selectedServiceID else { return false }
        return selectedServiceID.uriRepresentation().absoluteString == defaultApiServiceID
    }

    var body: some View {
        VStack {
            entityListView
                .id(refreshID)

            HStack {
                if selectedServiceID != nil {
                    if !isSelectedServiceDefault {
                        Button(action: {
                            defaultApiServiceID = selectedServiceID?.uriRepresentation().absoluteString
                        }) {
                            Label("Set as Default", systemImage: "star")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    else {
                        Button(action: {
                            // Still keep button without action to keep geometry persistent
                        }) {
                            Label("Default Service", systemImage: "star.fill")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .foregroundColor(.blue)
                    }
                    Spacer()
                    Button(action: onEdit) {
                        Label("Edit Selected", systemImage: "pencil")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .keyboardShortcut(.defaultAction)
                } else {
                    Spacer()
                }
                Button(action: onAdd) {
                    Label("Add New", systemImage: "plus")
                }
            }
        }
        .frame(minHeight: 300)
        .sheet(isPresented: $isShowingAddOrEditService) {
            let selectedApiService = apiServices.first(where: { $0.objectID == selectedServiceID }) ?? nil
            if selectedApiService == nil {
                APIServiceDetailView(viewContext: viewContext, apiService: nil)
            }
            else {
                APIServiceDetailView(viewContext: viewContext, apiService: selectedApiService)
            }

        }
    }

    private var entityListView: some View {
        EntityListView(
            selectedEntityID: $selectedServiceID,
            entities: apiServices,
            detailContent: detailContent,
            onRefresh: refreshList,
            getEntityColor: { _ in nil },
            getEntityName: { $0.name ?? "Untitled Service" },
            getEntityDefault: { $0.objectID.uriRepresentation().absoluteString == defaultApiServiceID },
            getEntityIcon: { "logo_" + ($0.type ?? "") },
            onEdit: {
                if selectedServiceID != nil {
                    isShowingAddOrEditService = true
                }
            }
        )
    }

    private func detailContent(service: APIServiceEntity?) -> some View {
        Group {
            if let service = service {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Type of API: \(AppConstants.defaultApiConfigurations[service.type!]?.name ?? "Unknown")")
                    Text("Selected Model: \(service.model ?? "Not specified")")
                    Text("Context size: \(service.contextSize)")
                    Text("Auto chat name generation: \(service.generateChatNames ? "Yes" : "No")")
                    //Text("Stream responses: \(service.useStreamResponse ? "Yes" : "No")")
                    Text("Default AI Assistant: \(service.defaultPersona?.name ?? "None")")
                }
            }
            else {
                Text("Select an API service to view details")
            }
        }
    }

    private func refreshList() {
        refreshID = UUID()
    }

    private func onAdd() {
        selectedServiceID = nil
        isShowingAddOrEditService = true
    }

    private func onEdit() {
        isShowingAddOrEditService = true
    }
}

struct APIServiceRowView: View {
    let service: APIServiceEntity

    var body: some View {
        VStack(alignment: .leading) {
            Text(service.name ?? "Untitled Service")
                .font(.headline)
            Text(service.type ?? "Unknown type")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}
