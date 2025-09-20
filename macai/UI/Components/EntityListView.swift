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
    var getEntityIcon: (Entity) -> String? = { _ in nil }
    let onEdit: (() -> Void)?
    let onMove: ((IndexSet, Int) -> Void)?
    var getEntityIdentifier: (Entity) -> AnyHashable = { entity in
        if let idProperty = entity.entity.propertiesByName["id"] as? NSAttributeDescription {
            switch idProperty.attributeType {
            case .UUIDAttributeType:
                if let uuid = entity.value(forKey: "id") as? UUID {
                    return AnyHashable(uuid)
                }
            case .stringAttributeType:
                if let stringValue = entity.value(forKey: "id") as? String {
                    return AnyHashable(stringValue)
                }
            case .integer16AttributeType,
                 .integer32AttributeType,
                 .integer64AttributeType:
                if let numberValue = entity.value(forKey: "id") as? NSNumber {
                    return AnyHashable(numberValue.int64Value)
                }
            default:
                break
            }
        }

        return AnyHashable(entity.objectID)
    }

    var body: some View {
        let listItems = entities.map { entity in
            EntityListItem(id: getEntityIdentifier(entity), entity: entity)
        }

        VStack {
            List(selection: $selectedEntityID) {
                ForEach(listItems) { item in
                    let entity = item.entity
                    EntityRowView(
                        color: getEntityColor?(entity),
                        name: getEntityName(entity),
                        defaultEntity: getEntityDefault(entity),
                        icon: getEntityIcon(entity),
                        showDragHandle: onMove != nil
                    )
                    .tag(entity.objectID)
                    .gesture(
                        TapGesture(count: 2).onEnded {
                            onEdit?()
                        }
                    )
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            selectedEntityID = entity.objectID
                        }
                    )
                }
                .onMove(perform: onMove)
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

extension EntityListView {
    private struct EntityListItem: Identifiable {
        let id: AnyHashable
        let entity: Entity
    }
}

struct EntityRowView: View {
    let color: Color?
    let name: String
    let defaultEntity: Bool
    let icon: String?
    let showDragHandle: Bool

    var body: some View {
        HStack {
            if let icon = icon {
                Image(icon)
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .antialiased(true)
                    .frame(width: 12, height: 12)
            }
            if let color = color {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
            }
            Text(name)

            Color.clear
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity)
                .frame(height: 24)

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

            if showDragHandle {
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
            }
        }
        .padding(4)
        .frame(height: 24)
    }
}
