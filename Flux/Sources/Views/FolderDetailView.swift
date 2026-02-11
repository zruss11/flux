import SwiftUI

struct FolderDetailView: View {
    @Bindable var conversationStore: ConversationStore
    let folder: ChatFolder
    var onOpenChat: (UUID) -> Void

    @State private var renamingConversationId: UUID?
    @State private var renameText = ""
    @FocusState private var isRenameFocused: Bool

    private var folderSummaries: [ConversationSummary] {
        conversationStore.summaries(forFolder: folder.id)
    }

    var body: some View {
        Group {
            if folderSummaries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(folderSummaries) { summary in
                            conversationRow(summary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - Rows

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

            Button("Remove from Folder") {
                conversationStore.moveConversation(summary.id, toFolder: nil)
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
        VStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.12))

            Text("This folder is empty")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.3))

            Text("Use the context menu on a chat\nto move it here")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.2))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Actions

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
