import SwiftUI
import UniformTypeIdentifiers

// MARK: - Image File Item

private struct ImageFileItem: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    let isImage: Bool
    let icon: String  // SF Symbol name
}

// MARK: - Image File Picker

struct ImageFilePickerView: View {
    var onSelect: ([URL]) -> Void
    var onCancel: () -> Void

    @State private var currentDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    @State private var selectedURLs: Set<URL> = []
    @State private var showHidden: Bool = false
    @State private var contents: [ImageFileItem] = []
    @State private var errorMessage: String?

    private static let imageTypes: Set<UTType> = [.png, .jpeg, .gif, .bmp, .tiff, .webP, .heic, .heif, .svg]

    var body: some View {
        VStack(spacing: 0) {
            // Breadcrumb bar
            breadcrumbBar
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

    // MARK: - Breadcrumb Bar

    private var pathSegments: [(name: String, url: URL)] {
        var segments: [(name: String, url: URL)] = []
        var url = currentDirectory.standardizedFileURL

        while url.path != "/" {
            let name = url.lastPathComponent
            segments.insert((name: name, url: url), at: 0)
            url = url.deletingLastPathComponent()
        }
        segments.insert((name: "/", url: URL(fileURLWithPath: "/")), at: 0)

        if segments.count > 4 {
            let ellipsis: [(name: String, url: URL)] = [segments[0], (name: "...", url: segments[0].url)]
            return ellipsis + segments.suffix(3)
        }

        return segments
    }

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(pathSegments.enumerated()), id: \.offset) { index, segment in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.3))
                    }

                    if segment.name == "..." {
                        Text("...")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.3))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                    } else {
                        Button {
                            navigateTo(segment.url)
                        } label: {
                            Text(segment.name)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(.white.opacity(0.06))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
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
            QuickLocation(name: "Pictures", icon: "photo.fill", url: home.appendingPathComponent("Pictures")),
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
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("No images in this directory")
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

    private func fileRow(_ item: ImageFileItem) -> some View {
        let isSelected = selectedURLs.contains(item.url)

        return Button {
            if item.isImage {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isSelected {
                        selectedURLs.remove(item.url)
                    } else {
                        selectedURLs.insert(item.url)
                    }
                }
            } else if item.isDirectory {
                navigateTo(item.url)
            }
        } label: {
            HStack(spacing: 10) {
                if item.isImage {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? .blue : .white.opacity(0.3))
                        .frame(width: 20)

                    Image(systemName: item.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 20)
                } else {
                    Image(systemName: item.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(.yellow.opacity(0.7))
                        .frame(width: 20)
                }

                Text(item.name)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
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
                    .fill(isSelected ? .blue.opacity(0.15) : .white.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
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

            if !selectedURLs.isEmpty {
                Text("\(selectedURLs.count) selected")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)

            Button {
                onSelect(Array(selectedURLs))
            } label: {
                Text("Add Images")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selectedURLs.isEmpty ? .white.opacity(0.3) : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(selectedURLs.isEmpty ? .blue.opacity(0.2) : .blue.opacity(0.6))
                    )
            }
            .buttonStyle(.plain)
            .disabled(selectedURLs.isEmpty)
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
                includingPropertiesForKeys: [.isDirectoryKey, .localizedNameKey, .contentTypeKey],
                options: options
            )

            let items: [ImageFileItem] = urls.compactMap { url in
                let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .localizedNameKey, .contentTypeKey])
                let isDirectory = resourceValues?.isDirectory ?? false
                let name = resourceValues?.localizedName ?? url.lastPathComponent
                let contentType = resourceValues?.contentType

                let isImage = !isDirectory && Self.isImageFile(contentType: contentType, pathExtension: url.pathExtension)

                // Only show directories and image files
                guard isDirectory || isImage else { return nil }

                let icon: String
                if isDirectory {
                    icon = "folder.fill"
                } else {
                    icon = Self.imageIcon(for: url.pathExtension)
                }

                return ImageFileItem(url: url, name: name, isDirectory: isDirectory, isImage: isImage, icon: icon)
            }

            // Sort: directories first, then images, alphabetical within each group
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

    private static func isImageFile(contentType: UTType?, pathExtension: String) -> Bool {
        if let contentType, contentType.conforms(to: .image) {
            return true
        }
        // Fallback: check extension
        let ext = pathExtension.lowercased()
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif", "svg", "ico", "avif"]
        return imageExtensions.contains(ext)
    }

    private static func imageIcon(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "heic", "heif", "webp", "avif":
            return "photo"
        case "gif":
            return "photo.badge.plus"
        case "svg":
            return "rectangle.3.group"
        case "bmp", "tiff", "tif":
            return "photo"
        default:
            return "photo"
        }
    }

    private func navigateTo(_ url: URL) {
        withAnimation(.easeInOut(duration: 0.2)) {
            currentDirectory = url
            selectedURLs.removeAll()
        }
    }
}
