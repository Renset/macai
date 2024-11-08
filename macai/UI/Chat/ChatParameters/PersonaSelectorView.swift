//
//  PersonaSelectorView.swift
//  macai
//
//  Created by Renat Notfullin on 08.11.2024.
//

import SwiftUI
import CoreData

struct GlassMorphicBackground: View {
    let color: Color
    let isSelected: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Rectangle()
            .fill(color)
            .opacity(isSelected ? 0.7 : 0.15)
    }
}

struct PersonaChipView: View {
    let persona: PersonaEntity
    let isSelected: Bool
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false
    
    private var personaColor: Color {
        Color(hex: persona.color ?? "#FFFFFF") ?? .white
    }
    
    var body: some View {
        Text(persona.name ?? "")
            .foregroundStyle(.primary)
            .frame(height: 32)
            .padding(.horizontal, 12)
            .background(
                GlassMorphicBackground(
                    color: personaColor,
                    isSelected: isSelected
                )
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        personaColor.opacity(isSelected ? 0.8 : 0.2),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(
                color: personaColor.opacity(isSelected ? 0.7 : 0),
                radius: isSelected ? 8 : 0,
                x: 0,
                y: 0
            )
            .shadow(
                color: personaColor.opacity(isHovered ? 0.2 : 0), // Slightly reduced hover glow
                radius: 4,
                x: 0,
                y: 0
            )
            .animation(.easeOut(duration: 0.2), value: isHovered)
            .animation(.easeOut(duration: 0.2), value: isSelected)
            .onHover { hovering in
                isHovered = hovering
            }
            .padding(4)
    }
}

struct PersonaSelectorView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \PersonaEntity.addedDate, ascending: true)],
        animation: .default)
    private var personas: FetchedResults<PersonaEntity>
    
    @ObservedObject var chat: ChatEntity
    @Environment(\.colorScheme) var colorScheme
    
    private func updatePersonaAndSystemMessage(to persona: PersonaEntity?) {
        chat.persona = persona
        chat.systemMessage = persona?.systemMessage ?? AppConstants.chatGptSystemMessage
        chat.objectWillChange.send()
        
        if let context = chat.managedObjectContext {
            do {
                try context.save()
            } catch {
                print("Error saving context after persona update: \(error)")
            }
        }
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(personas, id: \.self) { persona in
                    PersonaChipView(
                        persona: persona,
                        isSelected: chat.persona == persona
                    )
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            updatePersonaAndSystemMessage(to: persona)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, -8)
        }
        .frame(height: 72)
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let chat = ChatEntity(context: context)
    return PersonaSelectorView(chat: chat)
        .frame(width: 400)
}
