//
//  ChatSettingsView.swift
//  macai
//
//  Created by Codex on 16.01.2026.
//

import AppKit
import CoreData
import SwiftUI

/// Per-chat settings panel. Every control writes to the chat only: values the
/// chat has not overridden are inherited live from its assistant. Assistants
/// themselves are edited in Settings → AI Assistants.
struct ChatSettingsView: View {
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

    private var serviceSupportsImageGeneration: Bool {
        chat.effectiveApiService?.imageGenerationSupported ?? false
    }

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerSection
                assistantSection
                Divider()
                apiServiceSection
                Divider()
                modelSection
                Divider()
                temperatureSection
                Divider()
                contextSizeSection
                Divider()
                toolsSection
                resetSection
            }
            .padding(16)
            // Fully flexible frame so the controls' natural minimums don't
            // dictate the panel width (the parent owns sizing).
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            syncServiceSelection()
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

    private var headerSection: some View {
        HStack {
            Text("Chat Settings")
                .font(.headline)
            Spacer()
        }
    }

    private var assistantSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(chat.persona?.name ?? "No Assistant")
                .font(.title3)
            Text("Settings below apply to this chat only. Assistant defaults are edited in Settings → AI Assistants.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
    private var modelSection: some View {
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
                TextField("Enter model name", text: customModelBinding)
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
                            customModel = chat.effectiveModel
                        }
                    } else {
                        isCustomModel = false
                        customModel = newValue
                        updateModel(newValue)
                    }
                }

                if isCustomModel {
                    TextField("Enter custom model name", text: $customModel)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onChange(of: customModel) { _, newValue in
                            updateModel(newValue)
                        }
                }
            }
        }
    }

    private var temperatureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Temperature")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Slider(
                value: temperatureBinding,
                in: 0...1,
                step: 0.1
            )
            HStack {
                Text("0.0")
                Spacer()
                Text("\(String(format: "%.1f", chat.effectiveTemperature)) · \(chat.effectiveTemperature.temperatureDescriptor)")
                Spacer()
                Text("1.0")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var contextSizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Context size")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Slider(
                value: contextSizeBinding,
                in: 5...100,
                step: 5
            )

            Text("\(chat.effectiveContextSize) messages")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tools")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Toggle("Image generation", isOn: imageGenerationBinding)
                .disabled(!serviceSupportsImageGeneration)
                .help(serviceSupportsImageGeneration ? "" : "This API service does not support image generation.")

            capabilityRow("Image uploads", isAvailable: chat.allowsImageUploads)
            capabilityRow("PDF uploads", isAvailable: chat.allowsPdfUploads)

            Text("Uploads depend on the API service and can be changed in Settings → API Services.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var resetSection: some View {
        if chat.persona != nil {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                Button("Reset to Assistant Defaults") {
                    resetToAssistantDefaults()
                }
            }
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

    // MARK: - Bindings (all write to the chat, never to the assistant)

    private var temperatureBinding: Binding<Double> {
        Binding(
            get: { Double(chat.effectiveTemperature) },
            set: { newValue in
                chat.temperature = newValue
                chat.temperatureOverridden = true
                scheduleDebouncedSave()
            }
        )
    }

    private var contextSizeBinding: Binding<Double> {
        Binding(
            get: { Double(chat.effectiveContextSize) },
            set: { newValue in
                chat.contextSize = Int16(newValue)
                scheduleDebouncedSave()
            }
        )
    }

    private var imageGenerationBinding: Binding<Bool> {
        Binding(
            get: { chat.imageGenerationEnabled },
            set: { newValue in
                chat.imageGenerationMode = newValue ? 1 : 2
                viewContext.saveWithRetry(attempts: 1)
            }
        )
    }

    private var customModelBinding: Binding<String> {
        Binding(
            get: {
                customModel.isEmpty ? chat.effectiveModel : customModel
            },
            set: { newValue in
                customModel = newValue
                updateModel(newValue)
            }
        )
    }

    // MARK: - Actions

    private func updateModel(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, chat.gptModel != trimmed else { return }
        chat.gptModel = trimmed
        chat.modelOverridden = true
        scheduleDebouncedSave()
    }

    private func resetToAssistantDefaults() {
        flushPendingSave()
        chat.resetToAssistantDefaults()
        chat.objectWillChange.send()
        viewContext.saveWithRetry(attempts: 1)
        syncServiceSelection()
        refreshModels()
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

    // MARK: - Selection sync

    private func syncServiceSelection() {
        let currentID = chat.effectiveApiService?.objectID
        if let currentID,
           apiServices.contains(where: { $0.objectID == currentID }) {
            selectedServiceID = currentID
        } else {
            selectedServiceID = nil
        }
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
        let currentModel = chat.effectiveModel

        if availableModels.isEmpty {
            selectedModel = currentModel
            isCustomModel = true
            customModel = currentModel
            return
        }

        if availableModels.contains(currentModel) {
            selectedModel = currentModel
            isCustomModel = false
            customModel = currentModel
        } else {
            selectedModel = "custom"
            isCustomModel = true
            customModel = currentModel
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let chat = ChatEntity(context: context)
    return ChatSettingsView(chat: chat, onServiceChange: { _ in })
}
