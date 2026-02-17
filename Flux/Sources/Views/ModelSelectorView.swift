import SwiftUI

/// Toolbar pill button for selecting the AI model, matching the workspace and git branch pill style.
struct ModelSelectorPill: View {
    let selectedModelSpec: String?
    let isLocked: Bool
    let availableProviders: [ProviderInfo]
    let defaultModelSpec: String
    let onSelect: (String?) -> Void

    @State private var showPopover = false

    private var displayName: String {
        guard let spec = selectedModelSpec else { return "Default" }
        for provider in availableProviders {
            if let model = provider.models.first(where: { $0.modelSpec == spec }) {
                return model.name
            }
        }
        // Fallback: extract the part after the colon
        if let colonIndex = spec.firstIndex(of: ":") {
            return String(spec[spec.index(after: colonIndex)...])
        }
        return spec
    }

    private var textOpacity: Double {
        isLocked ? 0.35 : 0.6
    }

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(textOpacity))
                Text(displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(textOpacity))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            ModelPickerPopover(
                selectedModelSpec: selectedModelSpec,
                availableProviders: availableProviders,
                defaultModelSpec: defaultModelSpec
            ) { spec in
                showPopover = false
                onSelect(spec)
            }
        }
    }
}

/// Toolbar pill button for selecting a reasoning depth (thinking level).
struct ThinkingLevelPill: View {
    let selectedThinkingLevel: ThinkingLevel?
    let isLocked: Bool
    let defaultThinkingLevel: ThinkingLevel
    let onSelect: (ThinkingLevel?) -> Void

    @State private var showPopover = false

    private var displayLevel: ThinkingLevel {
        selectedThinkingLevel ?? defaultThinkingLevel
    }

    private var textOpacity: Double {
        isLocked ? 0.35 : 0.6
    }

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "brain")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(textOpacity))
                Text(displayLevel.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(textOpacity))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            ThinkingLevelPickerPopover(
                selectedThinkingLevel: selectedThinkingLevel,
                defaultThinkingLevel: defaultThinkingLevel
            ) { level in
                showPopover = false
                onSelect(level)
            }
        }
    }
}

struct ThinkingLevelPickerPopover: View {
    let selectedThinkingLevel: ThinkingLevel?
    let defaultThinkingLevel: ThinkingLevel
    let onSelect: (ThinkingLevel?) -> Void

    @State private var hoveredLevel: ThinkingLevel?
    @State private var hoveredDefault = false

    private var selectedLevel: ThinkingLevel {
        selectedThinkingLevel ?? defaultThinkingLevel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                onSelect(nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: selectedThinkingLevel == nil ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11))
                        .foregroundStyle(selectedThinkingLevel == nil ? .blue : .secondary)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Use Default")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                        Text(defaultThinkingLevel.displayName)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hoveredDefault ? Color.white.opacity(0.08) : (selectedThinkingLevel == nil ? Color.accentColor.opacity(0.08) : .clear))
                    .padding(.horizontal, 4)
            )
            .onHover { isHovered in
                hoveredDefault = isHovered
            }

            Divider()
                .padding(.vertical, 4)

            ForEach(ThinkingLevel.allCases, id: \.self) { level in
                let isSelected = selectedLevel == level

                Button {
                    onSelect(level)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 11))
                            .foregroundStyle(isSelected ? .blue : .secondary)

                        Text(level.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(hoveredLevel == level ? Color.white.opacity(0.08) : (isSelected ? Color.accentColor.opacity(0.08) : .clear))
                        .padding(.horizontal, 4)
                )
                .onHover { isHovered in
                    hoveredLevel = isHovered ? level : nil
                }
            }
        }
        .padding(.vertical, 4)
        .frame(width: 190)
        .background(.black.opacity(0.85))
    }
}

/// Popover content for browsing and selecting an AI model, grouped by provider.
struct ModelPickerPopover: View {
    let selectedModelSpec: String?
    let availableProviders: [ProviderInfo]
    let defaultModelSpec: String
    let onSelect: (String?) -> Void

    @State private var searchQuery = ""
    @State private var hoveredModelSpec: String? = nil
    @State private var hoveredDefault = false

    private var defaultModelName: String {
        for provider in availableProviders {
            if let model = provider.models.first(where: { $0.modelSpec == defaultModelSpec }) {
                return model.name
            }
        }
        if let colonIndex = defaultModelSpec.firstIndex(of: ":") {
            return String(defaultModelSpec[defaultModelSpec.index(after: colonIndex)...])
        }
        return defaultModelSpec
    }

    private var filteredProviders: [ProviderInfo] {
        if searchQuery.isEmpty { return availableProviders }
        let query = searchQuery.lowercased()
        return availableProviders.compactMap { provider in
            let providerNameMatches = provider.name.lowercased().contains(query)
            let matchingModels = provider.models.filter { model in
                providerNameMatches
                    || model.name.lowercased().contains(query)
                    || model.id.lowercased().contains(query)
            }
            if matchingModels.isEmpty { return nil }
            var filtered = provider
            filtered.models = matchingModels
            return filtered
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Search models\u{2026}", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            // Use Default row
            Button {
                onSelect(nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: selectedModelSpec == nil ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11))
                        .foregroundStyle(selectedModelSpec == nil ? .blue : .secondary)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Use Default")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                        Text(defaultModelName)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hoveredDefault ? Color.white.opacity(0.08) : (selectedModelSpec == nil ? Color.accentColor.opacity(0.08) : .clear))
                    .padding(.horizontal, 4)
            )
            .onHover { isHovered in
                hoveredDefault = isHovered
            }

            Divider()
                .padding(.vertical, 4)

            // Provider sections
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredProviders) { provider in
                        // Section header
                        Text(provider.name.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                            .padding(.bottom, 4)

                        // Model rows
                        ForEach(provider.models) { model in
                            let isSelected = selectedModelSpec == model.modelSpec

                            Button {
                                onSelect(model.modelSpec)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 11))
                                        .foregroundStyle(isSelected ? .blue : .secondary)

                                    Text(model.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)

                                    if model.reasoning {
                                        Text("Reasoning")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.white.opacity(0.7))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(
                                                Capsule()
                                                    .fill(Color.white.opacity(0.12))
                                            )
                                    }

                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(hoveredModelSpec == model.modelSpec ? Color.white.opacity(0.08) : (isSelected ? Color.accentColor.opacity(0.08) : .clear))
                                    .padding(.horizontal, 4)
                            )
                            .onHover { isHovered in
                                hoveredModelSpec = isHovered ? model.modelSpec : nil
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 280)
        .background(.black.opacity(0.85))
    }
}
