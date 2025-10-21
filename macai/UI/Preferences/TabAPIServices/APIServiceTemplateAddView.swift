//
//  APIServiceTemplateAddView.swift
//  macai
//
//  Created by Renat Notfullin on 19.09.2025
//

import AppKit
import CoreData
import SwiftUI

struct APIServiceTemplateAddView: View {
    @Environment(\.presentationMode) private var presentationMode
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \PersonaEntity.addedDate, ascending: true)],
        animation: .default
    )
    private var personas: FetchedResults<PersonaEntity>

    @StateObject private var viewModel: APIServiceTemplateAddViewModel
    private let onSwitchToExpert: (APIServiceTemplateExpertDestination) -> Void

    internal static let otherProviderTag = "__expert"

    @State private var selectedRowID: String = ""
    @FocusState private var isApiKeyFocused: Bool
    @State private var isServiceNameEditing: Bool = false
    @FocusState private var isServiceNameFocused: Bool

    init(
        viewContext: NSManagedObjectContext,
        onSwitchToExpert: @escaping (APIServiceTemplateExpertDestination) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: APIServiceTemplateAddViewModel(viewContext: viewContext))
        _personas = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \PersonaEntity.addedDate, ascending: true)],
            animation: .default
        )
        self.onSwitchToExpert = onSwitchToExpert
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            stepContent
            Spacer(minLength: 8)
            footer
        }
        .frame(minWidth: 520, minHeight: 420)
        .padding(20)
        .onAppear {
            if selectedRowID.isEmpty {
                selectedRowID = viewModel.selectedOptionID
            }
        }
        .onChange(of: viewModel.selectedOptionID) { newValue in
            if viewModel.currentStep == .selectTemplate && !newValue.isEmpty {
                selectedRowID = newValue
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add API Service")
                .font(.title2)
                .bold()
            Text(stepTitle(for: viewModel.currentStep))
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .selectTemplate:
            selectionStep
        case .configure:
            configurationStep
        case .validate:
            validationStep
        }
    }

    private var selectionStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a provider and model from the list below.")
                .foregroundColor(.secondary)

            GroupBox {
                TemplateOptionEntityList(
                    options: viewModel.templateOptions,
                    selectedID: $selectedRowID,
                    onSelectOption: { option in
                        selectedRowID = option.id
                        viewModel.selectOption(option)
                    },
                    onSelectExpert: {
                        selectedRowID = Self.otherProviderTag
                    }
                )
                .frame(height: 260)
            }
        }
    }

    private var configurationStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let provider = viewModel.selectedProvider, let model = viewModel.selectedModel {
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.displayName)
                        .font(.headline)
                    
                    HStack {
                        if isServiceNameEditing {
                            TextField("Service name", text: $viewModel.serviceName)
                                .textFieldStyle(.roundedBorder)
                                .focused($isServiceNameFocused)
                                .onSubmit {
                                    isServiceNameEditing = false
                                }
                                .onChange(of: viewModel.serviceName) { viewModel.handleNameChange($0) }
                        } else {
                            Text(viewModel.serviceName.isEmpty ? model.displayName : viewModel.serviceName)
                                .foregroundColor(.secondary)
                        }
                        
                        Button(action: {
                            if isServiceNameEditing {
                                isServiceNameEditing = false
                            } else {
                                isServiceNameEditing = true
                                isServiceNameFocused = true
                            }
                        }) {
                            Image(systemName: isServiceNameEditing ? "checkmark" : "pencil")
                                .foregroundColor(isServiceNameEditing ? .secondary : .blue)
                                .font(.body)
                        }
                        .buttonStyle(.plain)
                        .help(isServiceNameEditing ? "Save" : "Edit service name")
                        Spacer()
                        HStack(spacing: 12) {
                            Picker("Default AI Assistant", selection: Binding(
                                get: { viewModel.selectedPersona },
                                set: { viewModel.selectedPersona = $0 }
                            )) {
                                Text("None").tag(nil as PersonaEntity?)
                                ForEach(personas) { persona in
                                    Text(persona.name ?? "Untitled").tag(persona as PersonaEntity?)
                                }
                            }
                            .pickerStyle(.menu)
                        }.frame(width: 250)
                    }
                }
            }


                VStack(alignment: .leading, spacing: 12) {
                    
                    TextField("API key", text: $viewModel.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .focused($isApiKeyFocused)
                        .blur(radius: !viewModel.apiKey.isEmpty && !isApiKeyFocused ? 3 : 0, opaque: false)
                    
                    if let provider = viewModel.selectedProvider,
                       let configuration = AppConstants.defaultApiConfigurations[provider.id]
                    {
                        HStack(spacing: 16) {
                            if configuration.apiKeyRef.isEmpty == false,
                               let url = URL(string: configuration.apiKeyRef)
                            {
                                Link("API key guide", destination: url)
                                    .font(.footnote)
                            }
                        }
                        .foregroundColor(.blue)

                    }
                }.padding(.top, 12)

            Spacer()
            if let note = viewModel.selectedNote, note.isEmpty == false {
                NoteBox(note: note)
            }
        

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var validationStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch viewModel.validationState {
            case .idle, .running:
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Testing connection…")
                        .foregroundColor(.secondary)
                }
            case .success:
                Label(viewModel.validationMessage ?? "Connection test successful.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failure(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Label("Connection test failed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            }

            
            Text("Service saved as \(viewModel.serviceName). You can refine any settings in Expert mode.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch viewModel.currentStep {
        case .selectTemplate:
            HStack {
                Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                Spacer()
                Button("Continue") { handleSelectionContinue() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedRowID.isEmpty)
            }
        case .configure:
            HStack {
                Button("Back") { viewModel.goBack() }
                Spacer()
                Button("Continue") { _ = viewModel.advanceFromConfiguration() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.canAdvanceFromConfiguration)
            }
        case .validate:
            HStack {
                Button("Back") { viewModel.goBack() }
                    .disabled(viewModel.isTesting)

                Button("Edit in Expert mode") {
                    openExpertMode()
                }
                .disabled(viewModel.isTesting || viewModel.expertDestinationForCreatedService() == nil)

                Spacer()

                Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                }

                Button("Start using") {
                    startChatting()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.validationSucceeded || viewModel.createdServiceID == nil)
            }
        }
    }

    private func handleSelectionContinue() {
        if selectedRowID == Self.otherProviderTag {
            presentationMode.wrappedValue.dismiss()
            onSwitchToExpert(.new(preferredType: nil))
            return
        }

        if let destination = viewModel.advanceFromSelection() {
            presentationMode.wrappedValue.dismiss()
            onSwitchToExpert(destination)
        }
    }

    private func openExpertMode() {
        guard let destination = viewModel.expertDestinationForCreatedService() else { return }
        presentationMode.wrappedValue.dismiss()
        onSwitchToExpert(destination)
    }

    private func startChatting() {
        guard let serviceURI = viewModel.createdServiceURIString else { return }
        presentationMode.wrappedValue.dismiss()

        let requestId = UUID().uuidString
        let userInfo: [String: Any] = [
            "apiServiceURI": serviceURI,
            "windowId": 0,
            "requestId": requestId,
        ]

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(
                name: AppConstants.newChatNotification,
                object: nil,
                userInfo: userInfo
            )
        }
    }

    private func stepTitle(for step: APIServiceTemplateAddViewModel.Step) -> String {
        switch step {
        case .selectTemplate:
            return "Step 1 of 3 · Choose model"
        case .configure:
            return "Step 2 of 3 · Configure"
        case .validate:
            return "Step 3 of 3 · Test & finish"
        }
    }
}

private struct TemplateOptionEntityList: View {
    typealias TemplateOption = APIServiceTemplateAddViewModel.TemplateOption

    let options: [TemplateOption]
    @Binding var selectedID: String
    let onSelectOption: (TemplateOption) -> Void
    let onSelectExpert: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(options) { option in
                    let settings = option.model.settings
                    TemplateSelectableRow(
                        iconName: option.provider.iconName,
                        title: option.provider.displayName,
                        subtitle: option.model.displayName,
                        isSelected: selectedID == option.id,
                        showsVisionBadge: settings?.allowImageUploads ?? false,
                        showsImageGenBadge: settings?.imageGenerationSupported ?? false
                    ) {
                        selectedID = option.id
                        onSelectOption(option)
                    }
                }

                TemplateSelectableRow(
                    iconName: nil,
                    title: "Other",
                    subtitle: "Any model with any provider",
                    isSelected: selectedID == APIServiceTemplateAddView.otherProviderTag,
                    showsVisionBadge: false,
                    showsImageGenBadge: false
                ) {
                    selectedID = APIServiceTemplateAddView.otherProviderTag
                    onSelectExpert()
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TemplateSelectableRow: View {
    let iconName: String?
    let title: String
    let subtitle: String
    let isSelected: Bool
    let showsVisionBadge: Bool
    let showsImageGenBadge: Bool
    let action: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if let iconName {
                        Image(iconName)
                            .resizable()
                            .renderingMode(.template)
                            .interpolation(.high)
                            .frame(width: 16, height: 16)
                    }
                    else {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                    }

                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)

                    if showsVisionBadge {
                        CapabilityBadge(title: "Vision", color: .purple)
                    }
                    if showsImageGenBadge {
                        CapabilityBadge(title: "Image Gen", color: .blue)
                    }
                }

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

private struct NoteBox: View {
    let note: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundColor(.blue)
            Text(note)
                .font(.footnote)
                .foregroundColor(.primary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.08))
        )
    }
}
private struct CapabilityBadge: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(0.15))
            )
    }
}
