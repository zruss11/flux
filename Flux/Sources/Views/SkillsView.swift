import SwiftUI
import os

struct SkillsPillButton: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isPresented.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))

                Text("Skills")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct SkillsView: View {
    @Binding var isPresented: Bool
    @Binding var searchQuery: String
    var showsPill: Bool = true
    var onSkillSelected: (Skill) -> Void

    @State private var skills: [Skill] = []
    @State private var installingSkillId: UUID?
    @State private var permissionSheetSkill: Skill?

    private var filteredSkills: [Skill] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return skills }
        return skills.filter { skill in
            skill.name.localizedCaseInsensitiveContains(query)
            || (skill.description?.localizedCaseInsensitiveContains(query) ?? false)
            || skill.directoryName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            skillsList
                .onAppear {
                    loadSkills()
                }

            if showsPill {
                SkillsPillButton(isPresented: $isPresented)
            }
        }
        .onAppear {
            // Eagerly load skills so they're ready when the user triggers the dropdown
            loadSkills()
        }
        .onChange(of: isPresented) { _, presented in
            if presented {
                loadSkills()
            }
        }
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

    // MARK: - Skills List

    private var skillsList: some View {
        ScrollView {
            VStack(spacing: 2) {
                if filteredSkills.isEmpty {
                    Text(searchQuery.isEmpty ? "No skills available" : "No matching skills")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    ForEach(filteredSkills) { skill in
                        skillRow(skill)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(maxHeight: 350)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal, 8)
    }

    private func skillRow(_ skill: Skill) -> some View {
        Button {
            if skill.isInstalled {
                onSkillSelected(skill)
            } else {
                installSkill(skill)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: skill.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(skill.color.opacity(skill.isInstalled ? 0.9 : 0.4))
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(skill.isInstalled ? 0.9 : 0.5))

                    if let desc = skill.description {
                        Text(desc)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }

                Spacer()

                if !skill.isInstalled {
                    if installingSkillId == skill.id {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(skill.color.opacity(0.6))
                    }
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
    }

    // MARK: - Skills Pill

    // MARK: - Data Loading

    private func loadSkills() {
        Task {
            let loaded = await SkillsLoader.loadSkillsWithRecommendations()
            await MainActor.run {
                skills = loaded
            }
        }
    }

    // MARK: - Skill Installation

    private func installSkill(_ skill: Skill) {
        guard installingSkillId == nil else { return }
        installingSkillId = skill.id

        Task {
            do {
                try await SkillInstaller.install(directoryName: skill.directoryName)
                let reloaded = await SkillsLoader.loadSkillsWithRecommendations()
                await MainActor.run {
                    skills = reloaded
                    installingSkillId = nil
                    if !skill.requiredPermissions.isEmpty {
                        permissionSheetSkill = skill
                    }
                }
            } catch {
                Log.ui.error("Failed to install skill: \(error)")
                await MainActor.run {
                    installingSkillId = nil
                }
            }
        }
    }
}
