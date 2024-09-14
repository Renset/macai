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
            entityListView
                .id(refreshID)
            
            HStack {
                Spacer()
                if personas.count == 0 {
                    addPresetsButton
                }
                if selectedPersonaID != nil {
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
        .onChange(of: selectedPersonaID) { id in
            selectedPersona = personas.first(where: { $0.objectID == id })
            print("Selected Persona ID: \(id)")
            print("Selected Persona: \(selectedPersona?.name ?? "nil")")
        }
        .sheet(isPresented: $isShowingAddOrEditPersona) {
            PersonaDetailView(persona: $selectedPersona, onSave: {
                refreshList()
            }, onDelete: {
                selectedPersona = nil
            })
            .onAppear {
                print(">> View is here")
                print(">> Selected persona: \(selectedPersona?.name ?? "nil")")
            }
        }
    }
    
    private var entityListView: some View {
        EntityListView(
            selectedEntityID: $selectedPersonaID,
            entities: personas,
            detailContent: detailContent,
            onRefresh: refreshList,
            getEntityColor: getPersonaColor,
            getEntityName: getPersonaName
        )
    }
    
    private var addPresetsButton: some View {
        Button(action: {
            DatabasePatcher.addDefaultPersonasIfNeeded(context: viewContext, force: true)
        }) {
            Label("Add Personas from Presets", systemImage: "plus.circle")
        }
    }
    
    private func detailContent(persona: PersonaEntity?) -> some View {
        Group {
            if let persona = persona {
                Text(persona.systemMessage ?? "")
            } else {
                instructionText
            }
        }
    }
    
    private var instructionText: some View {
        Group {
            if personas.count == 0 {
                Text("There are no personas yet. Create one by clicking the 'Add New Persona' button below or add personas from presets.")
            } else if personas.count == 1 {
                Text("Select the only persona above to edit it, or create a new one")
            } else {
                Text("Select any of \(personas.count) personas to edit or create a new one")
            }
        }
    }
    
    private func onAdd() {
        selectedPersona = nil
        isShowingAddOrEditPersona = true
    }
    
    private func onEdit() {
        selectedPersona = personas.first(where: { $0.objectID == selectedPersonaID })
        isShowingAddOrEditPersona = true
        print("Opening Persona Detail View: \(selectedPersona?.name ?? "nil")")
    }
    
    private func getPersonaColor(persona: PersonaEntity) -> Color? {
        Color(hex: persona.color ?? "#FFFFFF") ?? .white
    }
    
    private func getPersonaName(persona: PersonaEntity) -> String {
        persona.name ?? "Unnamed Persona"
    }
    
    private func refreshList() {
        refreshID = UUID()
    }
}

struct PersonaDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.presentationMode) var presentationMode
    
    @Binding var persona: PersonaEntity?
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
            print(">> Persona: \(persona?.name ?? "")")
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
            personaToSave.id = UUID()
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
