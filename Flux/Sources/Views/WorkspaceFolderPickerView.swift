import SwiftUI

// MARK: - File Item

private struct FileItem: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    let icon: String  // SF Symbol name
}

// MARK: - Workspace Folder Picker

struct WorkspaceFolderPickerView: View {
    @Bindable var conversationStore: ConversationStore
    var onSelect: (URL) -> Void
    var onCancel: () -> Void

    @State private var currentDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    @State private var selectedURL: URL?
    @State private var showHidden: Bool = false
    @State private var contents: [FileItem] = []
    @State private var errorMessage: String?
    @State private var isEditingPath: Bool = false
    @State private var pathText: String = ""
    @FocusState private var pathFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Editable path bar
            pathBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            // Quick access row
            quickAccessRow
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            Divider()
                .overlay(Color.white.opacity(0.08))

            // Directory listing
            directoryListing

            Divider()
                .overlay(Color.white.opacity(0.08))

            // Bottom action bar
            bottomActionBar
        }
        .frame(maxWidth: .infinity, maxHeight: 460)
        .onAppear {
            loadContents()
        }
        .onChange(of: currentDirectory) { _, _ in
            loadContents()
        }
        .onChange(of: showHidden) { _, _ in
            loadContents()
        }
    }

    // MARK: - Path Bar

    private var pathBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))

            if isEditingPath {
                TextField("Enter path…", text: $pathText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .focused($pathFieldFocused)
                    .onSubmit {
                        commitPathEdit()
                    }
                    .onExitCommand {
                        cancelPathEdit()
                    }

                Button {
                    commitPathEdit()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.blue.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Go to path")

                Button {
                    cancelPathEdit()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
                .help("Cancel")
            } else {
                Button {
                    beginPathEdit()
                } label: {
                    Text(currentDirectory.path)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help("Click to edit path")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.white.opacity(isEditingPath ? 0.15 : 0.06), lineWidth: 1)
                )
        )
    }

    private func beginPathEdit() {
        pathText = currentDirectory.path
        withAnimation(.easeInOut(duration: 0.15)) {
            isEditingPath = true
        }
        // Delay focus slightly so the TextField is rendered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            pathFieldFocused = true
        }
    }

    private func commitPathEdit() {
        let trimmed = pathText.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded = NSString(string: trimmed).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            navigateTo(url)
        } else {
            // If the path is not a valid directory, show a brief error
            errorMessage = "Path not found or is not a directory:\n\(trimmed)"
        }

        withAnimation(.easeInOut(duration: 0.15)) {
            isEditingPath = false
        }
        pathFieldFocused = false
    }

    private func cancelPathEdit() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isEditingPath = false
        }
        pathFieldFocused = false
    }

    // MARK: - Quick Access Row

    private struct QuickLocation {
        let name: String
        let icon: String
        let url: URL
    }

    private var quickLocations: [QuickLocation] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            QuickLocation(name: "Home", icon: "house.fill", url: home),
            QuickLocation(name: "Desktop", icon: "desktopcomputer", url: home.appendingPathComponent("Desktop")),
            QuickLocation(name: "Documents", icon: "doc.text.fill", url: home.appendingPathComponent("Documents")),
            QuickLocation(name: "Downloads", icon: "arrow.down.circle.fill", url: home.appendingPathComponent("Downloads")),
            QuickLocation(name: "Developer", icon: "hammer.fill", url: home.appendingPathComponent("Developer")),
        ]
    }

    private var quickAccessRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(quickLocations, id: \.name) { location in
                    Button {
                        navigateTo(location.url)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: location.icon)
                                .font(.system(size: 10))
                            Text(location.name)
                                .font(.system(size: 11))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(.white.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Directory Listing

    private var directoryListing: some View {
        Group {
            if let errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.yellow.opacity(0.7))
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
            } else if contents.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Empty directory")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        // Parent directory navigation
                        if currentDirectory.path != "/" {
                            Button {
                                navigateTo(currentDirectory.deletingLastPathComponent())
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "arrow.up.doc.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.4))
                                        .frame(width: 20)

                                    Text("..")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.5))

                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.white.opacity(0.04))
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(contents) { item in
                            fileRow(item)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func fileRow(_ item: FileItem) -> some View {
        let isSelected = selectedURL == item.url

        return Button {
            if item.isDirectory {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedURL = item.url
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(item.isDirectory ? .yellow.opacity(0.7) : .white.opacity(0.4))
                    .frame(width: 20)

                Text(item.name)
                    .font(.system(size: 13))
                    .foregroundStyle(item.isDirectory ? .white.opacity(0.9) : .white.opacity(0.4))
                    .lineLimit(1)

                Spacer()

                if item.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? .white.opacity(0.1) : .white.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if item.isDirectory {
                    navigateTo(item.url)
                }
            }
        )
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $showHidden) {
                Text("Show Hidden")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            Spacer()

            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)

            Button {
                if let url = selectedURL {
                    onSelect(url)
                }
            } label: {
                Text("Select Folder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selectedURL == nil ? .white.opacity(0.3) : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(selectedURL == nil ? .blue.opacity(0.2) : .blue.opacity(0.6))
                    )
            }
            .buttonStyle(.plain)
            .disabled(selectedURL == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Functions

    private func loadContents() {
        errorMessage = nil
        do {
            let fm = FileManager.default
            let options: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]
            let urls = try fm.contentsOfDirectory(
                at: currentDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .localizedNameKey],
                options: options
            )

            let items: [FileItem] = urls.compactMap { url in
                let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .localizedNameKey])
                let isDirectory = resourceValues?.isDirectory ?? false
                let name = resourceValues?.localizedName ?? url.lastPathComponent
                let icon = isDirectory ? "folder.fill" : "doc.fill"
                return FileItem(url: url, name: name, isDirectory: isDirectory, icon: icon)
            }

            // Sort: directories first, then alphabetical by name
            contents = items.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        } catch {
            errorMessage = "Cannot access this directory.\n\(error.localizedDescription)"
            contents = []
        }
    }

    private func navigateTo(_ url: URL) {
        withAnimation(.easeInOut(duration: 0.2)) {
            currentDirectory = url
            selectedURL = nil
        }
    }
}
