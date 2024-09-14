//
//  EntityListView.swift
//  macai
//
//  Created by Renat Notfullin on 15.09.2024.
//

import SwiftUI
import CoreData

struct EntityListView<Entity: NSManagedObject & Identifiable, DetailContent: View>: View {
    @Binding var selectedEntityID: NSManagedObjectID?
    let entities: FetchedResults<Entity>
    let detailContent: (Entity?) -> DetailContent
    let onRefresh: () -> Void
    let getEntityColor: ((Entity) -> Color?)?
    let getEntityName: (Entity) -> String
    
    var body: some View {
        VStack {
            List(selection: $selectedEntityID) {
                ForEach(entities, id: \.objectID) { entity in
                    EntityRowView(color: getEntityColor?(entity), name: getEntityName(entity))
                        .tag(entity.objectID)
                }
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 200, maxHeight: 180)
            .cornerRadius(8)
            
            VStack(alignment: .leading) {
                HStack {
                    if let selectedEntity = entities.first(where: { $0.objectID == selectedEntityID }) {
                        detailContent(selectedEntity)
                            .padding(8)
                    } else {
                        detailContent(nil)
                            .padding(8)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()

            }
            .frame(maxHeight: 150)
        }
    }
}

struct EntityRowView: View {
    let color: Color?
    let name: String
    
    var body: some View {
        HStack {
            if let color = color {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
            }
            Text(name)
            Spacer()
        }
        .padding(4)
    }
}
