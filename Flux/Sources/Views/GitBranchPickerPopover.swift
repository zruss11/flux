import SwiftUI

/// Popover content listing available git branches for the workspace.
struct GitBranchPickerPopover: View {
    let branches: [String]
    let currentBranch: String
    let onSelect: (String) -> Void

    @State private var searchText = ""

    private var filteredBranches: [String] {
        if searchText.isEmpty { return branches }
        return branches.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Search branches…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            // Branch list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredBranches, id: \.self) { branch in
                        Button {
                            onSelect(branch)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: branch == currentBranch ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(branch == currentBranch ? .blue : .secondary)

                                Text(branch)
                                    .font(.system(size: 12, weight: branch == currentBranch ? .semibold : .regular))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(branch == currentBranch ? Color.accentColor.opacity(0.08) : .clear)
                                .padding(.horizontal, 4)
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 260)
        }
        .frame(width: 220)
    }
}
