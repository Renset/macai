//
//  PersonaSelectorView.swift
//  macai
//
//  Created by Renat Notfullin on 08.11.2024.
//

import CoreData
import SwiftUI

struct GlassMorphicBackground: View {
    let color: Color
    let isSelected: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Rectangle()
            .fill(color)
            .opacity(isSelected ? 0.6 : 0.12)
    }
}

struct PersonaChipView: View {
    let persona: PersonaEntity
    let isSelected: Bool
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false

    private let personaColor: Color

    init(persona: PersonaEntity, isSelected: Bool) {
        self.persona = persona
        self.isSelected = isSelected
        self.personaColor = Color(hex: persona.color ?? "#FFFFFF") ?? .white
    }

    var body: some View {
        Text(persona.name ?? "")
            .foregroundStyle(.primary)
            .frame(height: 32)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(personaColor.opacity(isSelected ? 0.6 : 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(personaColor.opacity(isSelected ? 0.8 : 0.2), lineWidth: isSelected ? 2 : 1)
                    )
                    .shadow(
                        color: personaColor.opacity(isSelected ? 0.7 : (isHovered ? 0.2 : 0)),
                        radius: isSelected ? 7 : 4
                    )
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
        sortDescriptors: [NSSortDescriptor(keyPath: \PersonaEntity.order, ascending: true)],
        animation: .default
    )
    private var personas: FetchedResults<PersonaEntity>

    private let edgeDarkColor = Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255)
    private let edgeLightColor = Color.white

    @ObservedObject var chat: ChatEntity
    @Environment(\.colorScheme) var colorScheme

    private func updatePersonaAndSystemMessage(to persona: PersonaEntity?) {
        chat.persona = persona
        chat.systemMessage = persona?.systemMessage ?? AppConstants.chatGptSystemMessage
        chat.objectWillChange.send()

        if let context = chat.managedObjectContext {
            try? context.save()
        }
    }

    var body: some View {
        ScrollViewReader { scrollView in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(personas, id: \.self) { persona in
                        PersonaChipView(persona: persona, isSelected: chat.persona == persona)
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    updatePersonaAndSystemMessage(to: persona)
                                }
                            }
                            .id(persona)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .overlay(alignment: .leading) {
                LinearGradient(
                    colors: [colorScheme == .dark ? edgeDarkColor : edgeLightColor, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 24)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .trailing) {
                LinearGradient(
                    colors: [.clear, colorScheme == .dark ? edgeDarkColor : edgeLightColor],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 24)
                .allowsHitTesting(false)
            }
            .onAppear {
                if let selectedPersona = chat.persona {
                    scrollView.scrollTo(selectedPersona, anchor: .center)
                }
            }
        }
        .frame(height: 64)
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let chat = ChatEntity(context: context)
    return PersonaSelectorView(chat: chat)
        .frame(width: 400)
}
