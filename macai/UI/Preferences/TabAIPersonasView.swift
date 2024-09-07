//
//  TabAIAgentsView.swift
//  macai
//
//  Created by Renat Notfullin on 07.09.2024.
//

import SwiftUI
import CoreData

struct TabAIPersonasView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \PersonaEntity.name, ascending: true)],
        animation: .default)
    private var personas: FetchedResults<PersonaEntity>
    
    @State private var isShowingAddPersona = false
    @State private var selectedPersona: PersonaEntity?
    
    var body: some View {
        VStack {
            List {
                ForEach(personas, id: \.objectID) { persona in
                    PersonaRowView(persona: persona)
                        .tag(persona.objectID)
                        .onTapGesture {
                            selectedPersona = persona
                        }
                        .background(selectedPersona?.objectID == persona.objectID ? Color.accentColor : .clear)
                        .foregroundColor(selectedPersona?.objectID == persona.objectID ? .white : .primary)
                        .cornerRadius(8)
                }
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 200, maxHeight: 120)
            .cornerRadius(8)
            
            
            VStack(alignment: .leading) {
                if selectedPersona != nil {
                    Text(selectedPersona?.systemMessage ?? "")
                } else {
                    Text("Select a persona or create a new one")
                }
                
                Spacer()
                
                HStack {
                    Spacer()
                    if (selectedPersona != nil) {
                        Button(action: {
                            isShowingAddPersona = true
                        }) {
                            Label("Edit Selected Persona", systemImage: "pencil")
                        }
                    }
                    Button(action: {
                        selectedPersona = nil
                        isShowingAddPersona = true
                    }) {
                        Label("Add Persona", systemImage: "plus")
                    }
                }
                
            }
            .frame(maxHeight: 150)
            
            
                
            
        }
        .sheet(isPresented: $isShowingAddPersona) {
            PersonaDetailView(persona: selectedPersona ?? nil)
        }
    }
}

struct PersonaRowView: View {
    let persona: PersonaEntity
    
    var body: some View {
        HStack {
            Circle()
                .fill(Color(hex: persona.color ?? "#FFFFFF") ?? .white)
                .frame(width: 12, height: 12)
            Text(persona.name ?? "Unnamed Persona")
            Spacer()
        }
        .padding(4)
    }
}

struct PersonaDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.presentationMode) var presentationMode
    
    let persona: PersonaEntity?
    
    @State private var name: String = ""
    @State private var color: Color = .white
    @State private var systemMessage: String = ""
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        Form {
            TextField("Name", text: $name)
            ColorPicker("Color", selection: $color)
            MessageInputView(
                text: $systemMessage,
                onEnter: {}
            )
            
            HStack {
                Button(persona == nil ? "Create Persona" : "Update Persona") {
                    savePersona()
                }
                Spacer()
                if persona != nil {
                    Button("Delete Persona") {
                        showingDeleteConfirmation = true
                    }
                }
            }
            
        }
        .padding()
        .frame(minWidth: 300, minHeight: 200)
        .onAppear {
            if let persona = persona {
                name = persona.name ?? ""
                color = Color(hex: persona.color ?? "#FFFFFF") ?? .white
                systemMessage = persona.systemMessage ?? ""
            }
        }
        .alert(isPresented: $showingDeleteConfirmation) {
            Alert(
                title: Text("Delete Persona"),
                message: Text("Are you sure you want to delete this persona? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    deletePersona()
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    private func savePersona() {
        let personaToSave = persona ?? PersonaEntity(context: viewContext)
        personaToSave.name = name
        personaToSave.color = color.toHex()
        personaToSave.systemMessage = systemMessage
        
        do {
            try viewContext.save()
            if persona == nil {
                presentationMode.wrappedValue.dismiss()
            }
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
    
    private func deletePersona() {
        if let personaToDelete = persona {
            viewContext.delete(personaToDelete)
            do {
                try viewContext.save()
                presentationMode.wrappedValue.dismiss()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

#Preview {
    TabAIPersonasView()
}
