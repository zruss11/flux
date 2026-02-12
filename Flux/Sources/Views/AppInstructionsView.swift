import SwiftUI

/// Settings panel for managing per-app dictation enhancement instructions.
///
/// Two-state UI:
/// 1. **Main list** — shows configured instructions as cards + an "Add App" button.
/// 2. **App picker** — searchable grid of installed apps; tapping one opens an inline instruction editor.
struct AppInstructionsView: View {
    @State private var instructions: [AppInstructions.Instruction] = []
    @State private var isPickingApp = false
    @State private var searchText = ""
    @State private var selectedApp: InstalledAppProvider.DiscoveredApp?
    @State private var draftInstruction = ""
    @State private var editingInstructionId: String?

    private let provider = InstalledAppProvider.shared
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Divider()
                .background(Color.white.opacity(0.1))

            if let app = selectedApp {
                // Instruction editor for selected app
                instructionEditor(for: app)
            } else if isPickingApp {
                // App picker grid
                appPickerView
            } else {
                // Main configured list
                configuredListView
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { reload() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if selectedApp != nil || isPickingApp {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            let wasEditingApp = selectedApp != nil
                            selectedApp = nil
                            draftInstruction = ""
                            editingInstructionId = nil
                            isPickingApp = wasEditingApp
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 13))
                        }
                        .foregroundStyle(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }

            Text(headerTitle)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)

            Text(headerSubtitle)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var headerTitle: String {
        if selectedApp != nil {
            return "Custom Instruction"
        } else if isPickingApp {
            return "Choose an App"
        } else {
            return "Per-App Dictation Instructions"
        }
    }

    private var headerSubtitle: String {
        if selectedApp != nil {
            return "Tell dictation enhancement how to rewrite text when this app is active."
        } else if isPickingApp {
            return "Select an app to customize dictation style."
        } else {
            return "Customize how voice dictation text is refined for each app."
        }
    }

    // MARK: - Configured List

    private var configuredListView: some View {
        VStack(spacing: 0) {
            if instructions.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "app.badge.checkmark")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.2))
                    Text("No per-app instructions yet")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Add an app to customize dictation style.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.3))
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(instructions) { instruction in
                            instructionCard(instruction)
                        }
                    }
                    .padding(16)
                }
            }

            Divider()
                .background(Color.white.opacity(0.1))

            // Add App button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPickingApp = true
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.blue)
                    Text("Add App")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .background(Color.white.opacity(0.03))
        }
    }

    private func instructionCard(_ instruction: AppInstructions.Instruction) -> some View {
        HStack(spacing: 12) {
            // App icon
            if let app = provider.app(forBundleId: instruction.bundleId) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.08))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "app.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.3))
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(instruction.appName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(instruction.instruction)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(2)
            }

            Spacer()

            HStack(spacing: 6) {
                // Edit button
                Button {
                    editInstruction(instruction)
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.white.opacity(0.06)))
                }
                .buttonStyle(.plain)

                // Delete button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        remove(id: instruction.id)
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.red.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - App Picker

    private var appPickerView: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
                TextField("Search apps…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Suggested apps section
            if searchText.isEmpty && !suggestedApps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SUGGESTED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.3))
                        .tracking(1)
                        .padding(.horizontal, 20)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(suggestedApps) { app in
                                suggestedAppPill(app)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 8)

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.horizontal, 16)
            }

            // All apps grid
            VStack(alignment: .leading, spacing: 8) {
                Text(searchText.isEmpty ? "ALL APPS" : "RESULTS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.3))
                    .tracking(1)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                ScrollView {
                    if filteredApps.isEmpty {
                        VStack(spacing: 6) {
                            Text("No apps found")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.4))
                            Text("Try a different search term.")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.25))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(filteredApps) { app in
                                appGridItem(app)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
        }
    }

    private func suggestedAppPill(_ app: InstalledAppProvider.DiscoveredApp) -> some View {
        let isConfigured = instructions.contains { $0.bundleId == app.bundleId }

        return Button {
            selectApp(app)
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(app.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(isConfigured ? 0.4 : 0.8))
                    .lineLimit(1)

                if isConfigured {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green.opacity(0.7))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(isConfigured ? 0.03 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func appGridItem(_ app: InstalledAppProvider.DiscoveredApp) -> some View {
        let isConfigured = instructions.contains { $0.bundleId == app.bundleId }

        return Button {
            selectApp(app)
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .opacity(isConfigured ? 0.5 : 1)

                    if isConfigured {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                            .offset(x: 4, y: -4)
                    }
                }

                Text(app.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(isConfigured ? 0.35 : 0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Instruction Editor

    private func instructionEditor(for app: InstalledAppProvider.DiscoveredApp) -> some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 16)

            // App identity
            VStack(spacing: 8) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)

                Text(app.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)

                Text(app.bundleId)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.bottom, 16)

            // Instruction text area
            VStack(alignment: .leading, spacing: 6) {
                Text("AI Instruction")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))

                TextEditor(text: $draftInstruction)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120, maxHeight: 200)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )

                if let suggestion = provider.suggestion(forBundleId: app.bundleId),
                   draftInstruction.isEmpty {
                    Button {
                        draftInstruction = suggestion.defaultInstruction
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                            Text("Use suggested instruction")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.blue.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            Spacer()

            Divider()
                .background(Color.white.opacity(0.1))

            // Save / Cancel buttons
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedApp = nil
                        draftInstruction = ""
                        editingInstructionId = nil
                    }
                } label: {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    saveInstruction(for: app)
                } label: {
                    Text(editingInstructionId != nil ? "Update" : "Save")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(draftInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      ? Color.blue.opacity(0.2)
                                      : Color.blue.opacity(0.7))
                        )
                }
                .buttonStyle(.plain)
                .disabled(draftInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
        }
    }

    // MARK: - Computed

    private var filteredApps: [InstalledAppProvider.DiscoveredApp] {
        let apps = provider.allApps
        if searchText.isEmpty { return apps }
        let query = searchText.lowercased()
        return apps.filter {
            $0.name.lowercased().contains(query) ||
            $0.bundleId.lowercased().contains(query)
        }
    }

    /// Suggested apps that are actually installed.
    private var suggestedApps: [InstalledAppProvider.DiscoveredApp] {
        let suggestedIds = Set(InstalledAppProvider.suggestions.map(\.bundleId))
        return provider.allApps.filter { suggestedIds.contains($0.bundleId) }
    }

    // MARK: - Actions

    private func selectApp(_ app: InstalledAppProvider.DiscoveredApp) {
        // If already configured, go to edit mode
        if let existing = instructions.first(where: { $0.bundleId == app.bundleId }) {
            draftInstruction = existing.instruction
            editingInstructionId = existing.id
        } else {
            // Pre-fill with suggestion if available
            if let suggestion = provider.suggestion(forBundleId: app.bundleId) {
                draftInstruction = suggestion.defaultInstruction
            } else {
                draftInstruction = ""
            }
            editingInstructionId = nil
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            selectedApp = app
        }
    }

    private func editInstruction(_ instruction: AppInstructions.Instruction) {
        if let app = provider.app(forBundleId: instruction.bundleId) {
            draftInstruction = instruction.instruction
            editingInstructionId = instruction.id
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedApp = app
            }
        }
    }

    private func saveInstruction(for app: InstalledAppProvider.DiscoveredApp) {
        let text = draftInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if let editId = editingInstructionId {
            AppInstructions.shared.upsert(
                .init(bundleId: app.bundleId, appName: app.name, instruction: text, id: editId)
            )
        } else {
            AppInstructions.shared.upsert(
                .init(bundleId: app.bundleId, appName: app.name, instruction: text)
            )
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            selectedApp = nil
            draftInstruction = ""
            editingInstructionId = nil
            isPickingApp = false
        }
        reload()
    }

    private func reload() {
        instructions = AppInstructions.shared.instructions
    }

    private func remove(id: String) {
        AppInstructions.shared.remove(id: id)
        reload()
    }
}
