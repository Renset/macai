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
                color: personaColor.opacity(isHovered ? 0.2 : 0),
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
        animation: .default
    )
    private var personas: FetchedResults<PersonaEntity>

    @ObservedObject var chat: ChatEntity
    @Environment(\.colorScheme) var colorScheme
    @State private var scrollViewWidth: CGFloat = 0

    private func updatePersonaAndSystemMessage(to persona: PersonaEntity?) {
        chat.persona = persona
        chat.systemMessage = persona?.systemMessage ?? AppConstants.chatGptSystemMessage
        chat.objectWillChange.send()

        if let context = chat.managedObjectContext {
            do {
                try context.save()
            }
            catch {
                print("Error saving context after persona update: \(error)")
            }
        }
    }

    private var gradientEdgeColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ScrollViewReader { scrollView in
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
                                .id(persona)  // Use persona as the identifier
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                    }
                    .onAppear {
                        scrollViewWidth = geometry.size.width
                        // If there's a selected persona, scroll to it
                        if let selectedPersona = chat.persona {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    scrollView.scrollTo(selectedPersona, anchor: .center)
                                }
                            }
                        }
                    }
                }

                // Edge gradients
                HStack {
                    LinearGradient(
                        gradient: Gradient(colors: [
                            gradientEdgeColor,
                            gradientEdgeColor.opacity(0),
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 24)

                    Spacer()

                    LinearGradient(
                        gradient: Gradient(colors: [
                            gradientEdgeColor.opacity(0),
                            gradientEdgeColor,
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 24)
                }
                .allowsHitTesting(false)
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
