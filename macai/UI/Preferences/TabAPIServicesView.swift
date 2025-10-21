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

    @State private var presentedSheet: PresentedSheet?
    @State private var selectedServiceID: NSManagedObjectID?
    @State private var refreshID = UUID()
    @State private var pendingPreferredType: String?
    @AppStorage("defaultApiService") private var defaultApiServiceID: String?

    private var isSelectedServiceDefault: Bool {
        guard let selectedServiceID = selectedServiceID else { return false }
        return selectedServiceID.uriRepresentation().absoluteString == defaultApiServiceID
    }

    var body: some View {
        VStack {
            entityListView
                .id(refreshID)

            HStack(spacing: 20) {
                if selectedServiceID != nil {
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .keyboardShortcut(.defaultAction)

                    Button(action: onDuplicate) {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    .buttonStyle(BorderlessButtonStyle())

                    if !isSelectedServiceDefault {
                        Button(action: {
                            defaultApiServiceID = selectedServiceID?.uriRepresentation().absoluteString
                        }) {
                            Label("Set as Default", systemImage: "star")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
                Spacer(minLength: 0)

                Menu {
                    Button("Add in Expert mode", action: presentExpertAdd)
                } label: {
                    Label("Add Service", systemImage: "plus")
                } primaryAction: {
                    presentSimpleAdd()
                }
                .frame(maxWidth: 200, alignment: .trailing)
            }
        }
        .frame(minHeight: 300)
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .addSimple:
                APIServiceTemplateAddView(viewContext: viewContext) { destination in
                    DispatchQueue.main.async {
                        switch destination {
                        case .new(let preferredType):
                            pendingPreferredType = preferredType
                            presentedSheet = .addExpert
                        case .existing(let objectID):
                            pendingPreferredType = nil
                            selectedServiceID = objectID
                            presentedSheet = .edit(objectID)
                        }
                    }
                }
            case .addExpert:
                APIServiceDetailView(
                    viewContext: viewContext,
                    apiService: nil,
                    preferredType: pendingPreferredType
                )
                .onDisappear {
                    pendingPreferredType = nil
                }
            case let .edit(objectID):
                if let selectedApiService = apiServices.first(where: { $0.objectID == objectID }) {
                    APIServiceDetailView(viewContext: viewContext, apiService: selectedApiService)
                }
                else {
                    EmptyView()
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
            getEntityName: { $0.name ?? "Untitled Service" },
            getEntityDefault: { $0.objectID.uriRepresentation().absoluteString == defaultApiServiceID },
            getEntityIcon: { "logo_" + ($0.type ?? "") },
            onEdit: {
                if let objectID = selectedServiceID {
                    presentedSheet = .edit(objectID)
                }
            },
            onMove: nil
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

    private func onDuplicate() {
        if let selectedService = apiServices.first(where: { $0.objectID == selectedServiceID }) {
            let newService = selectedService.copy() as! APIServiceEntity
            newService.name = (selectedService.name ?? "") + " Copy"
            newService.addedDate = Date()

            // Generate new UUID and copy the token
            let newServiceID = UUID()
            newService.id = newServiceID

            if let oldServiceIDString = selectedService.id?.uuidString {
                do {
                    if let token = try TokenManager.getToken(for: oldServiceIDString) {
                        try TokenManager.setToken(token, for: newServiceID.uuidString)
                    }
                }
                catch {
                    print("Error copying API token: \(error)")
                }
            }

            do {
                if newService.objectID.isTemporaryID {
                    try viewContext.obtainPermanentIDs(for: [newService])
                }
                try viewContext.save()
                refreshList()
            }
            catch {
                print("Error duplicating service: \(error)")
            }
        }
    }

    private func onEdit() {
        if let objectID = selectedServiceID {
            presentedSheet = .edit(objectID)
        }
    }

    private func presentSimpleAdd() {
        selectedServiceID = nil
        pendingPreferredType = nil
        presentedSheet = .addSimple
    }

    private func presentExpertAdd() {
        selectedServiceID = nil
        pendingPreferredType = nil
        presentedSheet = .addExpert
    }
}

extension TabAPIServicesView {
    private enum PresentedSheet: Identifiable {
        case addSimple
        case addExpert
        case edit(NSManagedObjectID)

        var id: String {
            switch self {
            case .addSimple:
                return "addSimple"
            case .addExpert:
                return "addExpert"
            case let .edit(objectID):
                return objectID.uriRepresentation().absoluteString
            }
        }
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
