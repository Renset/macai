//
//  TabAPIServices.swift
//  macai
//
//  Created by Renat Notfullin on 13.09.2024.
//

import SwiftUI
import CoreData

struct TabAPIServicesView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default)
    private var apiServices: FetchedResults<APIServiceEntity>
    
    @State private var isShowingAddOrEditService = false
    @State private var selectedServiceID: NSManagedObjectID?
    @State private var refreshID = UUID()
    
    var body: some View {
        VStack {
            entityListView
                .id(refreshID)
            
            HStack {
                Spacer()

                if selectedServiceID != nil {
                    Button(action: onEdit) {
                        Label("Edit Selected", systemImage: "pencil")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                Button(action: onAdd) {
                    Label("Add New", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingAddOrEditService) {
            let selectedApiService = apiServices.first(where: { $0.objectID == selectedServiceID }) ?? nil
            if (selectedApiService == nil) {
                APIServiceDetailView(viewContext: viewContext, apiService: nil)
            } else {
                APIServiceDetailView(viewContext: viewContext, apiService: selectedApiService)
                .onAppear {
                    print(selectedApiService)
                }
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
            getEntityName: { $0.name ?? "Untitled Service" }
        )
    }
    
    private func detailContent(service: APIServiceEntity?) -> some View {
        Group {
            if let service = service {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Type of API: \(service.type ?? "Unknown")")
                    Text("Selected Model: \(service.model ?? "Not specified")")
                    Text("Context size: \(service.contextSize)")
                    Text("Auto chat name generation: \(service.generateChatNames ? "Yes" : "No")")
                    //Text("Stream responses: \(service.useStreamResponse ? "Yes" : "No")")
                    Text("Default AI persona: \(service.defaultPersona?.name ?? "None")")
                }
            } else {
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