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
        sortDescriptors: [NSSortDescriptor(keyPath: \PersonaEntity.addedDate, ascending: true)],
        animation: .default)
    private var personas: FetchedResults<PersonaEntity>
    
    @State private var isShowingAddOrEditPersona = false
    @State private var selectedPersona: PersonaEntity?
    @State private var selectedPersonaID: NSManagedObjectID?
    @State private var refreshID = UUID()
    
    var body: some View {
        VStack {
            List(selection: $selectedPersonaID) {
                ForEach(personas, id: \.objectID) { persona in
                    PersonaRowView(persona: persona)
                        .tag(persona.objectID)
                }
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 200, maxHeight: 180)
            .cornerRadius(8)
            .onChange(of: selectedPersonaID) { id in
                if let persona = personas.first(where: { $0.objectID == id }) {
                    selectedPersona = persona
                }
            }
            .id(refreshID)
            
            VStack(alignment: .leading) {
                if selectedPersona != nil {
                    Text(selectedPersona?.systemMessage ?? "")
                        .padding(8)
                } else {
                     Group {
                        if personas.count == 0 {
                            Text("There are no personas yet. Create one by clicking the 'Add New Persona' button below or add personas from presets.")
                        } else if personas.count == 1 {
                            Text("Select the only persona above to edit it, or create a new one")
                        } else {
                            Text("Select any of \(personas.count) personas to edit or create a new one")
                        }
                    }
                     .padding(8)
                     .foregroundStyle(.secondary)
                    
                }
                
                Spacer()
                
                HStack {
                    Spacer()
                    if (selectedPersona != nil) {
                        Button(action: {
                            isShowingAddOrEditPersona = true
                        }) {
                            Label("Edit Selected Persona", systemImage: "pencil")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    if (personas.count == 0) {
                        Button(action: {
                            DatabasePatcher.addDefaultPersonasIfNeeded(context: viewContext, force: true)
                        }) {
                            Label("Add Personas from Presets", systemImage: "plus.circle")
                        }
                    }
                    Button(action: {
                        selectedPersona = nil
                        isShowingAddOrEditPersona = true
                    }) {
                        Label("Add New Persona", systemImage: "plus")
                    }
                }
            }
            .frame(maxHeight: 150)
        }
        .sheet(isPresented: $isShowingAddOrEditPersona) {
            PersonaDetailView(persona: selectedPersona ?? nil, onSave: {
                refreshList()
            }, onDelete: {
                selectedPersona = nil
            })
        }
    }
    
    private func refreshList() {
        refreshID = UUID()
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
    let onSave: () -> Void
    let onDelete: () -> Void
    
    @State private var name: String = ""
    @State private var color: Color = .white
    @State private var systemMessage: String = ""
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Name:")
            TextField("Enter AI persona name here", text: $name)
            
            ColorPicker("Color:", selection: $color)
                .padding(.top, 8)

            
            VStack(alignment: .leading) {
                Text("System message:")
                MessageInputView(
                    text: $systemMessage,
                    onEnter: {},
                    inputPlaceholderText: "Enter system message here",
                    cornerRadius: 4
                )
            }
            .padding(.top, 8)
            
            
            HStack {
                if persona != nil {
                    Button(action: {
                        showingDeleteConfirmation = true
                    }) {
                        Label("Delete", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                }
                
                Spacer()
                
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                
                Button(persona == nil ? "Create Persona" : "Update Persona") {
                    savePersona()
                    onSave()
                }
                .disabled(name.isEmpty || systemMessage.isEmpty)
            }
            .padding(.top, 16)
            
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
                    onDelete()
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
        if (persona == nil) {
            personaToSave.addedDate = Date()
        } else {
            personaToSave.editedDate = Date()
        }
        
        do {
            personaToSave.objectWillChange.send()
            try viewContext.save()
            presentationMode.wrappedValue.dismiss()
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
