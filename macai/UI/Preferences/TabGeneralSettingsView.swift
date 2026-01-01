//
//  TabGeneralSettingsView.swift
//  macai
//
//  Created by Renat on 31.01.2025.
//

import AppKit
import Sparkle
import SwiftUI
import AttributedText

struct TabGeneralSettingsView: View {
    private let previewCode = """
    func bar() -> Int {
        var 🍺: Double = 0
        var 🧑‍🔬: Double = 1
        while 🧑‍🔬 > 0 {
            🍺 += 1/🧑‍🔬
            🧑‍🔬 *= 2
            if 🍺 >= 2 {
                break
            }
        }
        return Int(🍺)
    }
    """
    @AppStorage("autoCheckForUpdates") var autoCheckForUpdates = true
    @AppStorage("chatFontSize") var chatFontSize: Double = 14.0
    @AppStorage("preferredColorScheme") private var preferredColorSchemeRaw: Int = 0
    @AppStorage("codeFont") private var codeFont: String = AppConstants.firaCode
    @AppStorage(PersistenceController.iCloudSyncEnabledKey) private var iCloudSyncEnabled: Bool = false
    @AppStorage(SettingsIndicatorKeys.generalSeen) private var generalSettingsSeen: Bool = false
    @Environment(\.colorScheme) private var systemColorScheme
    @StateObject private var cloudSyncManager = CloudSyncManager.shared
    @State private var selectedColorSchemeRaw: Int = 0
    @State private var codeResult: String = ""
    @State private var showRestartAlert: Bool = false
    @State private var pendingSyncState: Bool = false
    @State private var showSyncDebugLog: Bool = false
    @State private var isPurgingCloudData: Bool = false
    @State private var purgeError: String?

    private var preferredColorScheme: Binding<ColorScheme?> {
        Binding(
            get: {
                switch preferredColorSchemeRaw {
                case 1: return .light
                case 2: return .dark
                default: return nil
                }
            },
            set: { newValue in
                // This ugly solution is needed to workaround the SwiftUI (?) bug with the view not updated completely on setting theme to System
                if newValue == nil {
                    let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    preferredColorSchemeRaw = isDark ? 2 : 1
                    selectedColorSchemeRaw = 0

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        preferredColorSchemeRaw = 0
                    }
                }
                else {
                    switch newValue {
                    case .light: preferredColorSchemeRaw = 1
                    case .dark: preferredColorSchemeRaw = 2
                    case .none: preferredColorSchemeRaw = 0
                    case .some(_):
                        preferredColorSchemeRaw = 0
                    }
                    selectedColorSchemeRaw = preferredColorSchemeRaw
                }
            }
        )
    }

    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Use a plain VStack instead of Form so sections stretch to the full
            // available width (macOS Form tends to hug intrinsic content).
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 16) {
                        GridRow {
                            HStack {
                                Text("Chat Font Size")
                                Spacer()
                            }
                            .frame(width: 120)
                            .gridCellAnchor(.top)

                            VStack(spacing: 4) {
                                HStack {
                                    Text("A")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 12))

                                    Slider(value: $chatFontSize, in: 10...24, step: 1)
                                        .frame(width: 200)

                                    Text("A")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 20))
                                }
                                Text("Example \(Int(chatFontSize))pt")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: chatFontSize))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        
                        Divider()
                        
                        GridRow {
                            HStack {
                                Text("Code Font")
                                Spacer()
                            }
                            .frame(width: 120)
                            .gridCellAnchor(.top)
                                
                            VStack(alignment: .leading, spacing: 4) {
                                ScrollView {
                                    if let highlighted = HighlighterManager.shared.highlight(
                                        code: previewCode,
                                        language: "swift",
                                        theme: systemColorScheme == .dark ? "monokai-sublime" : "code-brewer",
                                        fontSize: chatFontSize
                                    ) {
                                        AttributedText(highlighted)
                                    } else {
                                        Text(previewCode)
                                            .font(.custom(codeFont, size: chatFontSize))
                                    }
                                }
                                
                                Picker("", selection: $codeFont) {
                                    Text("Fira Code").tag(AppConstants.firaCode)
                                    Text("PT Mono").tag(AppConstants.ptMono)
                                }
                                .pickerStyle(.segmented)
                            }
                            .padding(8)
                            .background(systemColorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.15) : Color(red: 0.96, green: 0.96, blue: 0.96))
                            .cornerRadius(6)
                            .frame(maxWidth: .infinity)
                            .frame(height: 140)
                        }
                        
                        Divider()
                        
                        GridRow {
                            HStack {
                                Text("Theme")
                                Spacer()
                            }
                            .frame(width: 120)
                            .gridCellAnchor(.top)

                            HStack(spacing: 12) {
                                ThemeButton(
                                    title: "macOS",
                                    isSelected: selectedColorSchemeRaw == 0,
                                    mode: .system
                                ) {
                                    preferredColorScheme.wrappedValue = nil
                                }

                                ThemeButton(
                                    title: "Light",
                                    isSelected: selectedColorSchemeRaw == 1,
                                    mode: .light
                                ) {
                                    preferredColorScheme.wrappedValue = .light
                                }

                                ThemeButton(
                                    title: "Dark",
                                    isSelected: selectedColorSchemeRaw == 2,
                                    mode: .dark
                                ) {
                                    preferredColorScheme.wrappedValue = .dark
                                }
                            }
                            .gridColumnAlignment(.trailing)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(8)
                }

                // iCloud Sync Section - hidden when DISABLE_ICLOUD flag is set or CloudKit is not configured
                #if !DISABLE_ICLOUD
                if AppConstants.cloudKitContainerIdentifier != nil {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center, spacing: 8) {
                                Text("iCloud Sync")
                                    .fontWeight(.medium)

                                Image(systemName: "info.circle")
                                    .foregroundColor(.secondary)
                                    .font(.callout)
                                    .help("""
                                    - Your data is transmitted securely to iCloud and stored by Apple; it is not accessible to the macai developer.
                                    - You can enable Advanced Data Protection in iCloud settings to encrypt your data so even Apple can't read your chats and messages.
                                    - Apple collects telemetry data, but it is anonymized.
                                    """)

                                SettingsIndicatorBadge(text: "Beta", color: .gray)

                                Spacer()

                                // Status indicator with label
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(syncStatusColor)
                                        .frame(width: 8, height: 8)
                                    Text(syncStatusText)
                                        .foregroundColor(.secondary)
                                        .font(.callout)
                                }

                                Button(action: {
                                    pendingSyncState = !iCloudSyncEnabled
                                    showRestartAlert = true
                                }) {
                                    Text(iCloudSyncEnabled ? "Turn Off" : "Turn On")
                                        .frame(width: 60)
                                }
                                .disabled(isPurgingCloudData)
                            }

                            Text("Syncs chats, messages, AI Assistants, and API Services across your devices. API keys are synced securely via iCloud Keychain.")
                                .foregroundColor(.secondary)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)

                            if iCloudSyncEnabled {
                                HStack {
                                    Spacer()
                                    Button("Show Log") {
                                        showSyncDebugLog = true
                                    }
                                    .buttonStyle(.link)
                                    .font(.callout)
                                }
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                #else
                // Show info when iCloud is disabled via build flag
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "icloud.slash")
                                .foregroundColor(.secondary)
                                .font(.title2)
                            
                            Text("iCloud Sync Disabled")
                                .fontWeight(.medium)
                            
                            Spacer()
                        }
                        
                        Text("iCloud Sync is disabled in this build via the DISABLE_ICLOUD compiler flag.")
                            .foregroundColor(.secondary)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("To enable iCloud Sync, remove DISABLE_ICLOUD from Build Settings → Swift Compiler → Active Compilation Conditions.")
                            .foregroundColor(.secondary)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Toggle("Automatically check for updates", isOn: $autoCheckForUpdates)
                    .onChange(of: autoCheckForUpdates) { newValue in
                        updaterController.updater.automaticallyChecksForUpdates = newValue
                    }

                Spacer()

                Button("Check for Updates Now") {
                    updaterController.checkForUpdates(nil)
                }
            }

        }
        .padding()
        .onAppear {
            self.selectedColorSchemeRaw = self.preferredColorSchemeRaw
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                generalSettingsSeen = true
            }
        }
        .alert("Restart Required", isPresented: $showRestartAlert) {
            Button("Cancel", role: .cancel) {}
            if pendingSyncState {
                Button("Enable & Restart") {
                    // Cache tokens first, then restore to cloud after enabling sync
                    let cachedTokens = TokenManager.cacheAllTokens()
                    iCloudSyncEnabled = pendingSyncState
                    TokenManager.restoreTokensToCloudKeychain(cachedTokens)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        restartApp()
                    }
                }
            } else {
                Button("Disable & Keep in iCloud") {
                    // Cache tokens in memory first, then restore to local keychain
                    let cachedTokens = TokenManager.cacheAllTokens()
                    iCloudSyncEnabled = pendingSyncState
                    TokenManager.restoreTokensToLocalKeychain(cachedTokens)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        restartApp()
                    }
                }
                Button("Disable & Delete from iCloud", role: .destructive) {
                    guard !isPurgingCloudData else { return }
                    isPurgingCloudData = true
                    // Cache all tokens in memory BEFORE any keychain operations
                    let cachedTokens = TokenManager.cacheAllTokens()
                    cloudSyncManager.purgeCloudData { result in
                        DispatchQueue.main.async {
                            isPurgingCloudData = false
                            switch result {
                            case .success:
                                purgeError = nil
                                TokenManager.clearCloudTokens()
                                // Restore cached tokens to local keychain AFTER clearing cloud
                                TokenManager.restoreTokensToLocalKeychain(cachedTokens)
                                iCloudSyncEnabled = pendingSyncState
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    restartApp()
                                }
                            case .failure(let error):
                                purgeError = error.localizedDescription
                            }
                        }
                    }
                }
            }
        } message: {
            Text(pendingSyncState
                 ? "Enabling iCloud sync requires restarting the app. Your existing data will be uploaded to iCloud."
                 : "Disabling iCloud sync requires restarting the app. Choose to keep or delete your iCloud copy; local data stays on this Mac and will stop syncing.")
        }
        .sheet(isPresented: $showSyncDebugLog) {
            SyncDebugLogView(cloudSyncManager: cloudSyncManager)
        }
        .alert("Couldn't remove iCloud data", isPresented: Binding<Bool>(
            get: { purgeError != nil },
            set: { newValue in if !newValue { purgeError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(purgeError ?? "Unknown error")
        }
    }

    private var syncStatusColor: Color {
        if !iCloudSyncEnabled {
            return .gray
        }
        switch cloudSyncManager.syncStatus {
        case .inactive:
            return .gray
        case .syncing:
            return .yellow
        case .synced:
            return .green
        case .error:
            return .red
        }
    }

    private var syncStatusText: String {
        if !iCloudSyncEnabled {
            return "Off"
        }
        switch cloudSyncManager.syncStatus {
        case .inactive:
            return "Off"
        case .syncing:
            return "Syncing..."
        case .synced:
            return "Up to date"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    private func restartApp() {
        let appPath = Bundle.main.bundlePath

        // Spawn a detached shell process that waits for the app to quit, then relaunches it
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; open \"\(appPath)\""]

        do {
            try task.run()
        } catch {
            print("Failed to schedule relaunch: \(error.localizedDescription)")
        }

        // Terminate the current instance
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Sync Debug Log View

struct SyncDebugLogView: View {
    @ObservedObject var cloudSyncManager: CloudSyncManager
    @Environment(\.dismiss) private var dismiss
    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("iCloud Sync Debug Log")
                    .font(.headline)

                Spacer()

                // Status
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(cloudSyncManager.syncStatus.displayText)
                        .foregroundColor(.secondary)
                        .font(.callout)
                }

                Spacer()

                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.checkbox)

                Button("Copy Log") {
                    let logText = cloudSyncManager.exportLogsAsText()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logText, forType: .string)
                }

                Button("Clear") {
                    cloudSyncManager.clearLogs()
                }

                Button("Close") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            // Log entries
            if cloudSyncManager.syncLogs.isEmpty {
                VStack {
                    Spacer()
                    Text("No log entries yet")
                        .foregroundColor(.secondary)
                    Text("Sync events will appear here")
                        .foregroundColor(.secondary)
                        .font(.callout)
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    List(cloudSyncManager.syncLogs) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.formattedTimestamp)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 90, alignment: .leading)

                            Text(entry.type)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(typeColor(entry.type))
                                .frame(width: 80, alignment: .leading)

                            Text(entry.message)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(entry.isError ? .red : .primary)
                                .textSelection(.enabled)
                        }
                        .id(entry.id)
                    }
                    .onChange(of: cloudSyncManager.syncLogs.count) { _ in
                        if autoScroll, let lastEntry = cloudSyncManager.syncLogs.last {
                            withAnimation {
                                proxy.scrollTo(lastEntry.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            Divider()

            // Footer with stats
            HStack {
                Text("\(cloudSyncManager.syncLogs.count) entries")
                    .font(.callout)
                    .foregroundColor(.secondary)

                Spacer()

                if let lastSync = cloudSyncManager.lastSyncDate {
                    Text("Last sync: \(lastSync.formatted(date: .abbreviated, time: .standard))")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 400)
    }

    private var statusColor: Color {
        switch cloudSyncManager.syncStatus {
        case .inactive:
            return .gray
        case .syncing:
            return .yellow
        case .synced:
            return .green
        case .error:
            return .red
        }
    }

    private func typeColor(_ type: String) -> Color {
        switch type {
        case "Error", "CloudKit":
            return .red
        case "Setup":
            return .blue
        case "Event":
            return .green
        case "RemoteChange":
            return .orange
        default:
            return .secondary
        }
    }
}
