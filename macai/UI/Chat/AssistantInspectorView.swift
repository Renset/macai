//
//  AssistantInspectorView.swift
//  macai
//
//  Created by Codex on 16.01.2026.
//

import AppKit
import CoreData
import SwiftUI

struct AssistantInspectorView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var chat: ChatEntity
    let onServiceChange: (APIServiceEntity) -> Void

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>

    @State private var selectedServiceID: NSManagedObjectID?
    @State private var selectedModel = ""
    @State private var isCustomModel = false
    @State private var customModel = ""
    @State private var fetchedModels: [String] = []
    @State private var isLoadingModels = false
    @State private var pendingSaveWorkItem: DispatchWorkItem?

    private var availableModels: [String] {
        if fetchedModels.isEmpty == false {
            return fetchedModels
        }
        guard let type = chat.effectiveApiService?.type else { return [] }
        return AppConstants.defaultApiConfigurations[type]?.models ?? []
    }

    private var supportsImageGeneration: Bool {
        chat.effectiveApiService?.imageGenerationSupported ?? false
    }

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection

            if let persona = chat.persona {
                personaSettings(persona)
            } else {
                emptyStateSection
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .padding(.top, 36)
        .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            syncServiceSelection()
            // Only persist when the stored value is actually stale.
            if supportsImageGeneration == false, chat.persona?.imageGenerationEnabled == true {
                chat.persona?.imageGenerationEnabled = false
                viewContext.saveWithRetry(attempts: 1)
            }
            refreshModels()
        }
        .onDisappear {
            flushPendingSave()
        }
        .onChange(of: chat.persona?.objectID) { _, _ in
            flushPendingSave()
            syncServiceSelection()
            refreshModels()
        }
        .onChange(of: chat.effectiveApiService?.objectID) { _, _ in
            syncServiceSelection()
            refreshModels()
        }
    }

    private func syncServiceSelection() {
        let currentID = chat.effectiveApiService?.objectID
        if let currentID,
           apiServices.contains(where: { $0.objectID == currentID }) {
            selectedServiceID = currentID
        } else {
            selectedServiceID = nil
        }
    }

    private var headerSection: some View {
        HStack {
            Text("Assistant Settings")
                .font(.headline)
            Spacer()
        }
    }

    @ViewBuilder
    private func personaSettings(_ persona: PersonaEntity) -> some View {
        personaHeaderSection(persona)
        Divider()
        apiServiceSection
        Divider()
        modelSection(persona)
        Divider()
        temperatureSection(persona)
        Divider()
        contextSizeSection(persona)
        Divider()
        toolsSection(persona)
        Spacer()
    }

    private func personaHeaderSection(_ persona: PersonaEntity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(persona.name ?? "Assistant")
                .font(.title3)
            Text(chat.effectiveApiService?.name ?? "No API Service")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var apiServiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("API Service")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("API Service", selection: $selectedServiceID) {
                Text("None").tag(nil as NSManagedObjectID?)
                ForEach(apiServices) { service in
                    Text(service.name ?? "Untitled")
                        .tag(service.objectID as NSManagedObjectID?)
                }
            }
            .labelsHidden()
            .onChange(of: selectedServiceID) { _, newValue in
                guard let newID = newValue else { return }
                guard let newService = apiServices.first(where: { $0.objectID == newID }) else { return }
                if newService.objectID != chat.effectiveApiService?.objectID {
                    onServiceChange(newService)
                }
            }
        }
    }

    @ViewBuilder
    private func modelSection(_ persona: PersonaEntity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Model")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                // Kept in the hierarchy permanently so the row height is stable;
                // toggling opacity avoids layout jumps below.
                ProgressView()
                    .controlSize(.small)
                    .opacity(isLoadingModels ? 1 : 0)
                    .accessibilityLabel("Loading models")
                    .accessibilityHidden(!isLoadingModels)
            }

            if availableModels.isEmpty {
                TextField("Enter model name", text: customModelBinding(for: persona))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            } else {
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
                        if customModel.isEmpty {
                            customModel = persona.model ?? ""
                        }
                    } else {
                        isCustomModel = false
                        customModel = newValue
                        updateModel(persona, value: newValue)
                    }
                }

                if isCustomModel {
                    TextField("Enter custom model name", text: $customModel)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onChange(of: customModel) { _, newValue in
                            updateModel(persona, value: newValue)
                        }
                }
            }
        }
    }

    private func temperatureSection(_ persona: PersonaEntity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Temperature")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Slider(
                value: temperatureBinding(for: persona),
                in: 0...1,
                step: 0.1
            )
            HStack {
                Text("0.0")
                Spacer()
                Text("\(String(format: "%.1f", persona.temperature)) · \(persona.temperature.temperatureDescriptor)")
                Spacer()
                Text("1.0")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func contextSizeSection(_ persona: PersonaEntity) -> some View {
        let effectiveContextSize = persona.contextSize == 0
            ? Int16(AppConstants.chatGptContextSize)
            : persona.contextSize

        return VStack(alignment: .leading, spacing: 8) {
            Text("Context size")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Slider(
                value: contextSizeBinding(for: persona),
                in: 5...100,
                step: 5
            )

            Text("\(Int(effectiveContextSize)) messages")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func toolsSection(_ persona: PersonaEntity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tools")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Toggle("Image generation", isOn: imageGenerationBinding(for: persona))
                .disabled(!supportsImageGeneration)
                .help(supportsImageGeneration ? "" : "This API service does not support image generation.")

            capabilityRow("Image uploads", isAvailable: chat.allowsImageUploads)
            capabilityRow("PDF uploads", isAvailable: chat.allowsPdfUploads)

            Text("Uploads depend on the API service and can be changed in Settings → API Services.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func capabilityRow(_ title: String, isAvailable: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isAvailable ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(isAvailable ? Color.green : Color.secondary)
            Text(title)
                .foregroundStyle(isAvailable ? Color.primary : Color.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(isAvailable ? "available" : "not available with this API service")")
    }

    private var emptyStateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select an assistant to edit its settings.")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    /// Coalesces rapid-fire edits (slider drags, typing) into one Core Data
    /// save — every save also triggers a CloudKit sync export.
    private func scheduleDebouncedSave() {
        pendingSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            viewContext.saveWithRetry(attempts: 1)
        }
        pendingSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func flushPendingSave() {
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        if viewContext.hasChanges {
            viewContext.saveWithRetry(attempts: 1)
        }
    }

    private func temperatureBinding(for persona: PersonaEntity) -> Binding<Double> {
        Binding(
            get: { Double(persona.temperature) },
            set: { newValue in
                persona.temperature = Float(newValue)
                scheduleDebouncedSave()
            }
        )
    }

    private func contextSizeBinding(for persona: PersonaEntity) -> Binding<Double> {
        Binding(
            get: { Double(persona.contextSize == 0 ? Int16(AppConstants.chatGptContextSize) : persona.contextSize) },
            set: { newValue in
                persona.contextSize = Int16(newValue)
                scheduleDebouncedSave()
            }
        )
    }

    private func imageGenerationBinding(for persona: PersonaEntity) -> Binding<Bool> {
        Binding(
            get: { persona.imageGenerationEnabled },
            set: { newValue in
                persona.imageGenerationEnabled = newValue
                viewContext.saveWithRetry(attempts: 1)
            }
        )
    }

    private func customModelBinding(for persona: PersonaEntity) -> Binding<String> {
        Binding(
            get: {
                customModel.isEmpty ? (persona.model ?? "") : customModel
            },
            set: { newValue in
                customModel = newValue
                updateModel(persona, value: newValue)
            }
        )
    }

    private func updateModel(_ persona: PersonaEntity, value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard persona.model != trimmed else { return }
        persona.model = trimmed
        scheduleDebouncedSave()
    }

    private func refreshModels() {
        guard let service = chat.effectiveApiService else {
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
                // Ignore responses that arrive after the user switched services or chats.
                guard chat.effectiveApiService?.objectID == requestedServiceID else { return }
                isLoadingModels = false
                if let models, !models.isEmpty, models != fetchedModels {
                    fetchedModels = models
                    syncModelSelection()
                }
            }
        }
    }

    private func syncModelSelection() {
        guard let persona = chat.persona else { return }
        let currentModel = persona.model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let defaultModel = AppConstants.defaultModel(for: chat.effectiveApiService?.type)

        if availableModels.isEmpty {
            selectedModel = currentModel
            isCustomModel = true
            customModel = currentModel
            return
        }

        if currentModel.isEmpty == false, availableModels.contains(currentModel) {
            selectedModel = currentModel
            isCustomModel = false
            customModel = currentModel
        } else if currentModel.isEmpty == false {
            selectedModel = "custom"
            isCustomModel = true
            customModel = currentModel
        } else if availableModels.contains(defaultModel) {
            selectedModel = defaultModel
            isCustomModel = false
            customModel = defaultModel
        } else if let firstModel = availableModels.first {
            selectedModel = firstModel
            isCustomModel = false
            customModel = firstModel
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let chat = ChatEntity(context: context)
    return AssistantInspectorView(chat: chat, onServiceChange: { _ in })
}
