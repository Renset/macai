//
//  TabAIAgentsView.swift
//  macai
//
//  Created by Renat Notfullin on 07.09.2024.
//

import CoreData
import SwiftUI
import UniformTypeIdentifiers

struct TabAIPersonasView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \PersonaEntity.order, ascending: true)],
        animation: .default
    )
    private var personas: FetchedResults<PersonaEntity>

    @State private var isShowingAddOrEditPersona = false
    @State private var selectedPersona: PersonaEntity?
    @State private var selectedPersonaID: NSManagedObjectID?
    @State private var refreshID = UUID()
    @State private var showingDeleteConfirmation = false
    @State private var personaToDelete: PersonaEntity?

    var body: some View {
        VStack {
            entityListView
                .id(refreshID)

            HStack(spacing: 20) {
                if selectedPersonaID != nil {
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .keyboardShortcut(.defaultAction)

                    Button(action: {
                        if let persona = personas.first(where: { $0.objectID == selectedPersonaID }) {
                            personaToDelete = persona
                            showingDeleteConfirmation = true
                        }

                    }) {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                Spacer()
                if personas.count == 0 {
                    addPresetsButton
                }
                Button(action: onAdd) {
                    Label("Add New", systemImage: "plus")
                }
            }
        }
        .frame(minHeight: 300)
        .onChange(of: selectedPersonaID) { id in
            selectedPersona = personas.first(where: { $0.objectID == id })
            print("Selected Assistant ID: \(id)")
            print("Selected Assistant: \(selectedPersona?.name ?? "nil")")
        }
        .sheet(isPresented: $isShowingAddOrEditPersona) {
            PersonaDetailView(
                persona: $selectedPersona,
                onSave: {
                    refreshList()
                },
                onDelete: {
                    selectedPersona = nil
                }
            )
        }
        .alert(isPresented: $showingDeleteConfirmation) {
            Alert(
                title: Text("Delete Assistant \(personaToDelete?.name ?? "Unknown")"),
                message: Text("Are you sure you want to delete this assistant? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    if let persona = personaToDelete {
                        viewContext.delete(persona)
                        try? viewContext.save()
                        selectedPersonaID = nil
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var entityListView: some View {
        EntityListView(
            selectedEntityID: $selectedPersonaID,
            entities: personas,
            detailContent: detailContent,
            onRefresh: refreshList,
            getEntityColor: getPersonaColor,
            getEntityName: getPersonaName,
            onEdit: {
                if let persona = personas.first(where: { $0.objectID == selectedPersonaID }) {
                    selectedPersona = persona
                    isShowingAddOrEditPersona = true
                }
            },
            onMove: { fromOffsets, toOffset in
                var updatedItems = Array(personas)
                updatedItems.move(fromOffsets: fromOffsets, toOffset: toOffset)

                for (index, item) in updatedItems.enumerated() {
                    item.order = Int16(index)
                }

                do {
                    try viewContext.save()
                }
                catch {
                    print("Failed to save reordering: \(error)")
                }
            }
        )
    }

    private var addPresetsButton: some View {
        Button(action: {
            DatabasePatcher.addDefaultPersonasIfNeeded(context: viewContext, force: true)
        }) {
            Label("Add AI Assistants from Presets", systemImage: "plus.circle")
        }
    }

    private func detailContent(persona: PersonaEntity?) -> some View {
        Group {
            if let persona = persona {
                Text(persona.systemMessage ?? "")
            }
            else {
                instructionText
            }
        }
    }

    private var instructionText: some View {
        Group {
            if personas.count == 0 {
                Text(
                    "There are no assistants yet. Create one by clicking the 'Add New Assistant' button below or add assistants from presets."
                )
            }
            else if personas.count == 1 {
                Text("Select the only assistant above to edit it, or create a new one")
            }
            else {
                Text("Select any of \(personas.count) assistants to edit or create a new one")
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
        print("Opening Assistant Detail View: \(selectedPersona?.name ?? "nil")")
    }

    private func getPersonaColor(persona: PersonaEntity) -> Color? {
        Color(hex: persona.color ?? "#FFFFFF") ?? .white
    }

    private func getPersonaName(persona: PersonaEntity) -> String {
        persona.name ?? "Unnamed Assistant"
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
    @State private var temperature: Float = 0.0

    var body: some View {
        VStack(alignment: .leading) {

            HStack {
                VStack(alignment: .leading) {
                    Text("Name:")
                    TextField("Enter AI Assistant name here", text: $name)
                }

                VStack {
                    Text("Color:")
                    ColorPicker("", selection: $color)

                }

            }
            .padding(.top, 8)

            VStack(alignment: .leading) {
                Text("System message:")
                MessageInputView(
                    text: $systemMessage,
                    attachedImages: .constant([]),
                    imageUploadsAllowed: false,
                    imageGenerationSupported: false,
                    onEnter: {},
                    onAddImage: {},
                    inputPlaceholderText: "Enter system message here",
                    cornerRadius: 4
                )
            }
            .padding(.top, 8)

            HStack {
                Slider(
                    value: $temperature,
                    in: 0...1,
                    step: 0.1
                ) {
                    Text("Temperature")
                } minimumValueLabel: {
                    Text("0.0")
                } maximumValueLabel: {
                    Text("1.0")
                }

                Text(getTemperatureLabel())
                    .frame(width: 90)
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

                Button(persona == nil ? "Create Assistant" : "Update Assistant") {
                    savePersona()
                    onSave()
                }
                .disabled(name.isEmpty || systemMessage.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 16)

        }
        .padding()
        .onAppear {
            print(">> Assistant: \(persona?.name ?? "")")
            if let persona = persona {
                name = persona.name ?? ""
                color = Color(hex: persona.color ?? "#FFFFFF") ?? .white
                systemMessage = persona.systemMessage ?? ""
                temperature = persona.temperature
            }
        }
        .alert(isPresented: $showingDeleteConfirmation) {
            Alert(
                title: Text("Delete Assistant"),
                message: Text("Are you sure you want to delete this assistant? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    deletePersona()
                    onDelete()
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func getTemperatureLabel() -> String {
        if temperature > 0.8 {
            return "Creative"
        }

        if temperature > 0.6 {
            return "Explorative"
        }

        if temperature > 0.4 {
            return "Balanced"
        }

        if temperature > 0.2 {
            return "Focused"
        }

        return "Deterministic"
    }

    private func savePersona() {
        let personaToSave = persona ?? PersonaEntity(context: viewContext)
        personaToSave.name = name
        personaToSave.color = color.toHex()
        personaToSave.temperature = round(temperature * 10) / 10
        personaToSave.systemMessage = systemMessage
        if persona == nil {
            personaToSave.addedDate = Date()
            personaToSave.id = UUID()

            let fetchRequest: NSFetchRequest<PersonaEntity> = PersonaEntity.fetchRequest()
            do {
                let existingPersonas = try viewContext.fetch(fetchRequest)
                for existingPersona in existingPersonas {
                    existingPersona.order += 1
                }
                personaToSave.order = 0
            }
            catch {
                personaToSave.order = 0
                print("Error fetching personas for order: \(error)")
            }
        }
        else {
            personaToSave.editedDate = Date()
        }

        do {
            personaToSave.objectWillChange.send()
            try viewContext.save()
            presentationMode.wrappedValue.dismiss()
        }
        catch {
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
            }
            catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

#Preview {
    TabAIPersonasView()
}
