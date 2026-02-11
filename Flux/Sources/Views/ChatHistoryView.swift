import SwiftUI

struct ChatHistoryView: View {
    @Bindable var conversationStore: ConversationStore
    var onOpenChat: (UUID) -> Void
    var onNewChat: () -> Void
    var onOpenFolder: (ChatFolder) -> Void

    @State private var searchText = ""
    @State private var showNewFolderField = false
    @State private var newFolderName = ""
    @State private var renamingConversationId: UUID?
    @State private var renameText = ""
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isNewFolderFocused: Bool
    @FocusState private var isRenameFocused: Bool

    private var filteredSummaries: [ConversationSummary] {
        let unfiled = conversationStore.unfiledSummaries
        guard !searchText.isEmpty else { return unfiled }
        return unfiled.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredFolders: [ChatFolder] {
        guard !searchText.isEmpty else { return conversationStore.folders }
        return conversationStore.folders.filter { folder in
            folder.name.localizedCaseInsensitiveContains(searchText) ||
            conversationStore.summaries(forFolder: folder.id).contains {
                $0.title.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private var groupedSummaries: [(String, [ConversationSummary])] {
        let grouped = Dictionary(grouping: filteredSummaries) { $0.timeGroup }
        return ConversationSummary.TimeGroup.allCases.compactMap { group in
            guard let items = grouped[group], !items.isEmpty else { return nil }
            return (group.rawValue, items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))

                TextField("Search chats...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .focused($isSearchFocused)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.06))
            )
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Folders section
                    if !filteredFolders.isEmpty || showNewFolderField {
                        foldersSection
                    }

                    // Unfiled conversations grouped by time
                    ForEach(groupedSummaries, id: \.0) { group, items in
                        sectionHeader(group)

                        ForEach(items) { summary in
                            conversationRow(summary)
                        }
                    }

                    if filteredSummaries.isEmpty && filteredFolders.isEmpty && !showNewFolderField {
                        emptyState
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Folders Section

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Folders")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .textCase(.uppercase)

                Spacer()

                Button {
                    showNewFolderField = true
                    newFolderName = ""
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            if showNewFolderField {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.yellow.opacity(0.7))
                        .frame(width: 16)

                    TextField("Folder name...", text: $newFolderName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .focused($isNewFolderFocused)
                        .onSubmit {
                            commitNewFolder()
                        }
                        .onAppear {
                            IslandWindowManager.shared.makeKeyIfNeeded()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isNewFolderFocused = true
                            }
                        }

                    Button {
                        commitNewFolder()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.green.opacity(0.8))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showNewFolderField = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
                .padding(.horizontal, 4)
            }

            ForEach(filteredFolders) { folder in
                folderRow(folder)
            }
        }
    }

    private func folderRow(_ folder: ChatFolder) -> some View {
        Button {
            onOpenFolder(folder)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.yellow.opacity(0.7))
                    .frame(width: 16)

                Text(folder.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                Spacer()

                Text("\(folder.conversationIds.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.0001)))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename Folder") {
                // For simplicity, use an inline rename approach
                // This could be enhanced with a popover in the future
            }
            Button("Delete Folder", role: .destructive) {
                conversationStore.deleteFolder(id: folder.id)
            }
        }
    }

    // MARK: - Conversation Rows

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.4))
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func conversationRow(_ summary: ConversationSummary) -> some View {
        Group {
            if renamingConversationId == summary.id {
                renameRow(summary)
            } else {
                chatRow(summary)
            }
        }
    }

    private func chatRow(_ summary: ConversationSummary) -> some View {
        Button {
            onOpenChat(summary.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(width: 16)

                Text(summary.title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Text(summary.lastMessageAt.relativeShort)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.0001)))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename") {
                renameText = summary.title
                renamingConversationId = summary.id
            }

            Menu("Move to Folder") {
                ForEach(conversationStore.folders) { folder in
                    Button(folder.name) {
                        conversationStore.moveConversation(summary.id, toFolder: folder.id)
                    }
                }
                Divider()
                Button("New Folder...") {
                    showNewFolderField = true
                }
            }

            Divider()

            Button("Delete", role: .destructive) {
                conversationStore.deleteConversation(id: summary.id)
            }
        }
    }

    private func renameRow(_ summary: ConversationSummary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 16)

            TextField("Chat title...", text: $renameText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .focused($isRenameFocused)
                .onSubmit {
                    commitRename(summary.id)
                }
                .onAppear {
                    IslandWindowManager.shared.makeKeyIfNeeded()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isRenameFocused = true
                    }
                }

            Button {
                commitRename(summary.id)
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.green.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
        .padding(.horizontal, 4)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.15))

            Text("No conversations yet")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Actions

    private func commitNewFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            showNewFolderField = false
            return
        }
        conversationStore.createFolder(name: name)
        showNewFolderField = false
        newFolderName = ""
    }

    private func commitRename(_ id: UUID) {
        let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            renamingConversationId = nil
            return
        }
        conversationStore.renameConversation(id: id, to: title)
        renamingConversationId = nil
    }
}

// MARK: - Date Formatting Helper

extension Date {
    var relativeShort: String {
        let now = Date()
        let interval = now.timeIntervalSince(self)

        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        if interval < 604800 { return "\(Int(interval / 86400))d" }
        if interval < 2592000 { return "\(Int(interval / 604800))w" }
        return "\(Int(interval / 2592000))mo"
    }
}
