//
//  EntityListView.swift
//  macai
//
//  Created by Renat Notfullin on 15.09.2024.
//

import CoreData
import SwiftUI

struct EntityListView<Entity: NSManagedObject & Identifiable, DetailContent: View>: View {
    @Binding var selectedEntityID: NSManagedObjectID?
    let entities: FetchedResults<Entity>
    let detailContent: (Entity?) -> DetailContent
    let onRefresh: () -> Void
    let getEntityColor: ((Entity) -> Color?)?
    let getEntityName: (Entity) -> String
    var getEntityDefault: (Entity) -> Bool = { _ in false }

    var body: some View {
        VStack {
            List(selection: $selectedEntityID) {
                ForEach(entities, id: \.objectID) { entity in
                    EntityRowView(
                        color: getEntityColor?(entity),
                        name: getEntityName(entity),
                        defaultEntity: getEntityDefault(entity)
                    )
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
                    }
                    else {
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
    let defaultEntity: Bool

    var body: some View {
        HStack {
            if let color = color {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
            }
            Text(name)

            Spacer()
            if defaultEntity {
                Text("Default")
                    .foregroundColor(.white)
                    .font(.caption)
                    .padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.blue)
                    )
            }
        }
        .padding(4)
    }
}
