import SwiftUI
import AppKit

struct SkillsMarketplaceView: View {
    @State private var skills: [Skill] = []
    @State private var searchText = ""
    @State private var installingSkillId: UUID?
    @State private var uninstallingSkillId: UUID?
    @State private var confirmingUninstallId: UUID?
    @State private var showCustomInstall = false
    @State private var customDirectoryName = ""
    @State private var customInstallError: String?
    @State private var isInstallingCustom = false
    @State private var permissionSheetSkill: Skill?
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isCustomFieldFocused: Bool

    private var filteredSkills: [Skill] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return skills }
        return skills.filter { skill in
            skill.name.localizedCaseInsensitiveContains(query)
            || (skill.description?.localizedCaseInsensitiveContains(query) ?? false)
            || skill.directoryName.localizedCaseInsensitiveContains(query)
        }
    }

    private var installedSkills: [Skill] {
        filteredSkills.filter { $0.isInstalled }
    }

    private var curatedSkills: [Skill] {
        filteredSkills.filter { !$0.isInstalled }
    }

    private var curatedByCategory: [(SkillCategory, [Skill])] {
        let grouped = Dictionary(grouping: curatedSkills) { skill -> SkillCategory in
            SkillCatalog.recommended
                .first { $0.directoryName == skill.directoryName }?
                .category ?? .productivity
        }
        return SkillCategory.allCases.compactMap { category in
            guard let skills = grouped[category], !skills.isEmpty else { return nil }
            return (category, skills)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            ScrollView {
                VStack(spacing: 16) {
                    installedSection
                    curatedSection
                    customInstallSection
                    getMoreSection
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .onAppear { loadSkills() }
        .overlay {
            if let skill = permissionSheetSkill {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { permissionSheetSkill = nil }

                SkillPermissionSheet(skill: skill) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        permissionSheetSkill = nil
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: permissionSheetSkill != nil)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))

            TextField("Search skills...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.9))
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - Installed Section

    private var installedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("INSTALLED", count: installedSkills.count)

            if installedSkills.isEmpty {
                emptyState(
                    icon: "sparkles",
                    message: searchText.isEmpty
                        ? "No skills installed yet"
                        : "No matching installed skills"
                )
            } else {
                VStack(spacing: 2) {
                    ForEach(installedSkills) { skill in
                        installedSkillRow(skill)
                    }
                }
            }
        }
    }

    // MARK: - Curated Section

    private var curatedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !curatedSkills.isEmpty {
                sectionHeader("CURATED", count: curatedSkills.count)

                VStack(spacing: 10) {
                    ForEach(curatedByCategory, id: \.0) { category, skills in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.rawValue)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.3))
                                .padding(.leading, 4)

                            VStack(spacing: 2) {
                                ForEach(skills) { skill in
                                    curatedSkillRow(skill)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Custom Install Section

    private var customInstallSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showCustomInstall.toggle()
                    if showCustomInstall {
                        isCustomFieldFocused = true
                    } else {
                        customDirectoryName = ""
                        customInstallError = nil
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.square.dashed")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 24, height: 24)

                    Text("Install Custom Skill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))

                    Spacer()

                    Image(systemName: showCustomInstall ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.0001))
                )
            }
            .buttonStyle(.plain)

            if showCustomInstall {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        TextField("skill-name", text: $customDirectoryName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                            .focused($isCustomFieldFocused)
                            .onSubmit { installCustomSkill() }

                        Button {
                            installCustomSkill()
                        } label: {
                            if isInstallingCustom {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 20, height: 20)
                            } else {
                                Text("Install")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.1))
                        )
                        .disabled(customDirectoryName.isEmpty || isInstallingCustom)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )

                    Text("Use letters, numbers, hyphens, and underscores")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.leading, 4)

                    if let error = customInstallError {
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundStyle(.red.opacity(0.8))
                            .padding(.leading, 4)
                    }
                }
                .padding(.horizontal, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Get More Section

    private var getMoreSection: some View {
        Button {
            if let url = URL(string: "https://skills.sh/") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "safari")
                    .font(.system(size: 16))
                    .foregroundStyle(.blue.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.blue.opacity(0.15)))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Discover More Skills")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Browse skills.sh for community skills")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.blue.opacity(0.12), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.bottom, 4)
    }

    // MARK: - Skill Rows

    private func installedSkillRow(_ skill: Skill) -> some View {
        HStack(spacing: 10) {
            Image(systemName: skill.icon)
                .font(.system(size: 14))
                .foregroundStyle(skill.color.opacity(0.9))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))

                if let desc = skill.description {
                    Text(desc)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }

            Spacer()

            if uninstallingSkillId == skill.id {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 20, height: 20)
            } else if confirmingUninstallId == skill.id {
                Button {
                    uninstallSkill(skill)
                } label: {
                    Text("Remove?")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        confirmingUninstallId = skill.id
                    }
                    // Auto-dismiss after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if confirmingUninstallId == skill.id {
                                confirmingUninstallId = nil
                            }
                        }
                    }
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.red.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.0001))
        )
    }

    private func curatedSkillRow(_ skill: Skill) -> some View {
        Button {
            installSkill(skill)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: skill.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(skill.color.opacity(0.5))
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))

                    if let desc = skill.description {
                        Text(desc)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.3))
                            .lineLimit(1)
                    }

                    if !skill.requiredPermissions.isEmpty {
                        Text("Requires permissions")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.orange.opacity(0.8))
                    }
                }

                Spacer()

                if installingSkillId == skill.id {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 20, height: 20)
                } else {
                    Text("GET")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(skill.color.opacity(0.8))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(skill.color.opacity(0.12))
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.0001))
            )
        }
        .buttonStyle(.plain)
        .disabled(installingSkillId != nil)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))

            Text("\(count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.25))

            Spacer()
        }
        .padding(.leading, 4)
    }

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.2))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Actions

    private func loadSkills() {
        Task {
            let loaded = await SkillsLoader.loadSkillsWithRecommendations()
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    skills = loaded
                }
            }
        }
    }

    private func installSkill(_ skill: Skill) {
        guard installingSkillId == nil else { return }
        installingSkillId = skill.id

        Task {
            do {
                try await SkillInstaller.install(directoryName: skill.directoryName)
                let reloaded = await SkillsLoader.loadSkillsWithRecommendations()
                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        skills = reloaded
                        installingSkillId = nil
                    }
                    if !skill.requiredPermissions.isEmpty {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            permissionSheetSkill = skill
                        }
                    }
                }
            } catch {
                print("[SkillsMarketplace] Failed to install skill: \(error)")
                await MainActor.run { installingSkillId = nil }
            }
        }
    }

    private func uninstallSkill(_ skill: Skill) {
        guard uninstallingSkillId == nil else { return }
        confirmingUninstallId = nil
        uninstallingSkillId = skill.id

        Task {
            do {
                try await SkillInstaller.uninstall(directoryName: skill.directoryName)
                let reloaded = await SkillsLoader.loadSkillsWithRecommendations()
                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        skills = reloaded
                        uninstallingSkillId = nil
                    }
                }
            } catch {
                print("[SkillsMarketplace] Failed to uninstall skill: \(error)")
                await MainActor.run { uninstallingSkillId = nil }
            }
        }
    }

    private func installCustomSkill() {
        let name = customDirectoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isInstallingCustom else { return }

        customInstallError = nil
        isInstallingCustom = true

        Task {
            do {
                try await SkillInstaller.installCustom(directoryName: name)
                let reloaded = await SkillsLoader.loadSkillsWithRecommendations()
                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        skills = reloaded
                        customDirectoryName = ""
                        isInstallingCustom = false
                        showCustomInstall = false
                    }
                }
            } catch let error as SkillInstaller.CustomInstallError {
                await MainActor.run {
                    isInstallingCustom = false
                    switch error {
                    case .invalidName:
                        customInstallError = "Invalid name. Use only letters, numbers, and hyphens."
                    case .alreadyExists:
                        customInstallError = "A skill with this name already exists."
                    case .directoryCreationFailed:
                        customInstallError = "Failed to create skill directory."
                    case .fileWriteFailed:
                        customInstallError = "Failed to write skill file."
                    }
                }
            } catch {
                await MainActor.run {
                    isInstallingCustom = false
                    customInstallError = "Installation failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
