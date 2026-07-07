//
//  TabAIAgentsView.swift
//  macai
//
//  Created by Renat Notfullin on 07.09.2024.
//

import CoreData
import SwiftUI

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
        .onChange(of: selectedPersonaID) { _, id in
            selectedPersona = personas.first(where: { $0.objectID == id })
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
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>

    @Binding var persona: PersonaEntity?
    let onSave: () -> Void
    let onDelete: () -> Void

    @State private var name: String = ""
    @State private var color: Color = .white
    @State private var systemMessage: String = ""
    @State private var showingDeleteConfirmation = false
    @State private var temperature: Float = AppConstants.defaultPersonaTemperature
    @State private var selectedService: APIServiceEntity?
    @State private var model: String = ""
    @State private var selectedModel: String = ""
    @State private var isCustomModel = false
    @State private var fetchedModels: [String] = []
    @State private var isLoadingModels = false
    @State private var contextSize: Float = Float(AppConstants.chatGptContextSize)
    @State private var useStreamResponse = true
    @State private var generateChatNames = true
    @State private var imageGenerationEnabled = false

    private var serviceConfiguration: AppConstants.defaultApiConfiguration? {
        guard let type = selectedService?.type else { return nil }
        return AppConstants.defaultApiConfigurations[type]
    }

    private var availableModels: [String] {
        if fetchedModels.isEmpty == false {
            return fetchedModels
        }
        return serviceConfiguration?.models ?? []
    }

    private var supportsImageGeneration: Bool {
        selectedService?.imageGenerationSupported
            ?? serviceConfiguration?.imageGenerationSupported
            ?? false
    }

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
                    attachedFiles: .constant([]),
                    isInferenceInProgress: false,
                    imageUploadsAllowed: false,
                    pdfUploadsAllowed: false,
                    imageGenerationSupported: false,
                    onEnter: {},
                    onAddImage: {},
                    onAddFile: {},
                    onStopInference: {},
                    inputPlaceholderText: "Enter system message here",
                    cornerRadius: 4
                )
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 4) {
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

                    Text(temperature.temperatureDescriptor)
                        .frame(width: 90)
                }

                Text("1.0 is recommended when using reasoning models.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            Divider()
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 10) {
                Text("Service & Model")
                    .font(.headline)

                HStack {
                    Text("API Service:")
                        .frame(width: 100, alignment: .leading)

                    Picker("API Service", selection: $selectedService) {
                        Text("None").tag(nil as APIServiceEntity?)
                        ForEach(apiServices) { service in
                            Text(service.name ?? "Untitled").tag(service as APIServiceEntity?)
                        }
                    }
                    .labelsHidden()
                }

                if selectedService != nil {
                    HStack {
                        HStack(spacing: 6) {
                            Text("Model:")
                            // Kept in the hierarchy permanently so the row height is stable;
                            // toggling opacity avoids layout jumps below.
                            ProgressView()
                                .controlSize(.small)
                                .opacity(isLoadingModels ? 1 : 0)
                                .accessibilityLabel("Loading models")
                                .accessibilityHidden(!isLoadingModels)
                        }
                        .frame(width: 100, alignment: .leading)

                        Picker("Model", selection: $selectedModel) {
                            ForEach(availableModels.sorted(), id: \.self) { modelName in
                                Text(modelName).tag(modelName)
                            }
                            Divider()
                            Text("Custom Model…").tag("custom")
                        }
                        .labelsHidden()
                        .onChange(of: selectedModel) { _, newValue in
                            if newValue == "custom" {
                                isCustomModel = true
                            }
                            else {
                                isCustomModel = false
                                model = newValue
                            }
                        }
                    }

                    if isCustomModel {
                        TextField("Enter custom model name", text: $model)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }

                    HStack {
                        Slider(
                            value: $contextSize,
                            in: 5...100,
                            step: 5
                        ) {
                            Text("Context size")
                        } minimumValueLabel: {
                            Text("5")
                        } maximumValueLabel: {
                            Text("100")
                        }

                        Text(String(format: ("%.0f messages"), contextSize))
                            .frame(width: 90)
                    }
                }
            }
            .padding(.top, 4)

            Divider()
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("Behavior")
                    .font(.headline)

                Toggle(isOn: $generateChatNames) {
                    Text("Automatically generate chat names")
                }

                Toggle(isOn: $useStreamResponse) {
                    Text("Use streamed responses")
                }
            }

            Divider()
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("Tools")
                    .font(.headline)

                Toggle(isOn: $imageGenerationEnabled) {
                    Text("Image generation")
                }
                .disabled(!supportsImageGeneration)
                .help(supportsImageGeneration ? "" : "This API service does not support image generation.")
            }

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
                .disabled(
                    name.isEmpty
                    || systemMessage.isEmpty
                    || selectedService == nil
                    || model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 16)

        }
        .padding()
        .onAppear {
            if let persona = persona {
                name = persona.name ?? ""
                color = Color(hex: persona.color ?? "#FFFFFF") ?? .white
                systemMessage = persona.systemMessage ?? ""
                temperature = persona.temperature
                selectedService = persona.apiService
                model = persona.model ?? ""
                contextSize = Float(persona.contextSize == 0 ? Int16(AppConstants.chatGptContextSize) : persona.contextSize)
                useStreamResponse = persona.useStreamResponse
                generateChatNames = persona.generateChatNames
                imageGenerationEnabled = persona.imageGenerationEnabled
            } else {
                selectedService = apiServices.first(where: { $0.isDefault }) ?? apiServices.first
                if let config = serviceConfiguration {
                    model = config.defaultModel
                    selectedModel = config.defaultModel
                }
                contextSize = Float(AppConstants.chatGptContextSize)
                useStreamResponse = true
                generateChatNames = true
                imageGenerationEnabled = false
            }

            syncModelSelection()
            refreshModels()
            if supportsImageGeneration == false {
                imageGenerationEnabled = false
            }
        }
        .onChange(of: selectedService) { _, _ in
            if let config = serviceConfiguration {
                if model.isEmpty {
                    model = config.defaultModel
                }
                if selectedModel.isEmpty {
                    selectedModel = config.defaultModel
                }
            }
            syncModelSelection()
            refreshModels()
            if supportsImageGeneration == false {
                imageGenerationEnabled = false
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

    private func syncModelSelection() {
        if availableModels.contains(model) {
            selectedModel = model
            isCustomModel = false
        } else if model.isEmpty == false {
            selectedModel = "custom"
            isCustomModel = true
        }
    }

    private func refreshModels() {
        guard let service = selectedService else {
            fetchedModels = []
            isLoadingModels = false
            syncModelSelection()
            return
        }

        // Show the cached list right away so the selected model is visible
        // immediately; a background refresh updates it afterwards.
        if let serviceID = service.id, let cached = ModelsCache.shared.models(for: serviceID) {
            fetchedModels = cached
        } else {
            fetchedModels = []
        }
        syncModelSelection()

        guard let config = AppConstants.defaultApiConfigurations[service.type ?? ""],
              config.modelsFetching else {
            isLoadingModels = false
            return
        }

        let requestedServiceID = service.objectID
        isLoadingModels = true
        Task {
            let models = await APIServiceManager.fetchRemoteModels(
                context: viewContext,
                serviceID: requestedServiceID
            )
            await MainActor.run {
                // Ignore responses that arrive after the user switched services.
                guard selectedService?.objectID == requestedServiceID else { return }
                isLoadingModels = false
                if let models, !models.isEmpty, models != fetchedModels {
                    fetchedModels = models
                    syncModelSelection()
                }
            }
        }
    }

    private func savePersona() {
        let personaToSave = persona ?? PersonaEntity(context: viewContext)
        personaToSave.name = name
        personaToSave.color = color.toHex()
        personaToSave.temperature = round(temperature * 10) / 10
        personaToSave.systemMessage = systemMessage
        personaToSave.apiService = selectedService
        personaToSave.model = model
        personaToSave.contextSize = Int16(contextSize)
        personaToSave.useStreamResponse = useStreamResponse
        personaToSave.generateChatNames = generateChatNames
        personaToSave.imageGenerationEnabled = imageGenerationEnabled
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

        if personaToSave.objectID.isTemporaryID {
            do {
                try viewContext.obtainPermanentIDs(for: [personaToSave])
            }
            catch {
                print("Failed to obtain permanent ID for persona: \(error)")
            }
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
