import AppKit
import os

/// Discovers installed applications on the system and provides their metadata (name, bundle ID, icon).
///
/// Scans `/Applications` and `~/Applications` for `.app` bundles and caches the results.
/// Also provides a curated set of suggested apps with default instruction placeholders.
@MainActor
final class InstalledAppProvider {
    static let shared = InstalledAppProvider()

    struct DiscoveredApp: Identifiable, Hashable {
        let id: String          // bundleId
        let name: String
        let bundleId: String
        let icon: NSImage

        func hash(into hasher: inout Hasher) {
            hasher.combine(bundleId)
        }

        static func == (lhs: DiscoveredApp, rhs: DiscoveredApp) -> Bool {
            lhs.bundleId == rhs.bundleId
        }
    }

    struct SuggestedApp {
        let bundleId: String
        let name: String
        let defaultInstruction: String
    }

    /// Pre-curated suggestions for popular apps.
    static let suggestions: [SuggestedApp] = [
        SuggestedApp(bundleId: "com.apple.Safari", name: "Safari",
                     defaultInstruction: "Help me with web browsing, research, and finding information online."),
        SuggestedApp(bundleId: "com.google.Chrome", name: "Google Chrome",
                     defaultInstruction: "Help me with web browsing, research, and finding information online."),
        SuggestedApp(bundleId: "company.thebrowser.Browser", name: "Arc",
                     defaultInstruction: "Help me with web browsing, research, and finding information online."),
        SuggestedApp(bundleId: "com.apple.dt.Xcode", name: "Xcode",
                     defaultInstruction: "Be technical and precise. Help with Swift/SwiftUI code, debugging, and build issues."),
        SuggestedApp(bundleId: "com.microsoft.VSCode", name: "VS Code",
                     defaultInstruction: "Be technical and precise. Help with coding, debugging, and development workflows."),
        SuggestedApp(bundleId: "com.tinyspeck.slackmacgap", name: "Slack",
                     defaultInstruction: "Be casual and concise. Help draft messages, summarize threads, and manage channels."),
        SuggestedApp(bundleId: "com.apple.MobileSMS", name: "Messages",
                     defaultInstruction: "Be casual and friendly. Help me draft messages and replies."),
        SuggestedApp(bundleId: "com.apple.mail", name: "Mail",
                     defaultInstruction: "Help me draft professional emails, summarize threads, and manage my inbox."),
        SuggestedApp(bundleId: "com.apple.Notes", name: "Notes",
                     defaultInstruction: "Help me organize thoughts, outline ideas, and take structured notes."),
        SuggestedApp(bundleId: "com.apple.Terminal", name: "Terminal",
                     defaultInstruction: "Be technical. Help with shell commands, scripts, and system administration."),
        SuggestedApp(bundleId: "com.figma.Desktop", name: "Figma",
                     defaultInstruction: "Help with UI/UX design decisions, layout feedback, and design system guidance."),
        SuggestedApp(bundleId: "com.apple.finder", name: "Finder",
                     defaultInstruction: "Help me organize files, find documents, and manage my filesystem."),
        SuggestedApp(bundleId: "notion.id", name: "Notion",
                     defaultInstruction: "Help me organize documents, create templates, and structure my workspace."),
        SuggestedApp(bundleId: "com.linear", name: "Linear",
                     defaultInstruction: "Help me manage issues, write clear bug reports, and plan sprints."),
        SuggestedApp(bundleId: "com.spotify.client", name: "Spotify",
                     defaultInstruction: "Help me discover music, create playlists, and find songs."),
    ]

    /// All discovered installed apps, sorted by name.
    private(set) var allApps: [DiscoveredApp] = []

    private init() {
        refresh()
    }

    /// Re-scan the file system for installed apps.
    func refresh() {
        var found: [String: DiscoveredApp] = [:]

        let searchPaths = [
            "/Applications",
            "/System/Applications",
            NSHomeDirectory() + "/Applications",
        ]

        for searchPath in searchPaths {
            scanDirectory(URL(fileURLWithPath: searchPath), into: &found, depth: 0, maxDepth: 2)
        }

        allApps = found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        Log.appMonitor.info("InstalledAppProvider found \(self.allApps.count) apps")
    }

    /// Look up a discovered app by bundle ID.
    func app(forBundleId bundleId: String) -> DiscoveredApp? {
        allApps.first { $0.bundleId == bundleId }
    }

    /// Get the suggestion for a bundle ID if one exists.
    func suggestion(forBundleId bundleId: String) -> SuggestedApp? {
        Self.suggestions.first { $0.bundleId == bundleId }
    }

    // MARK: - Private

    private func scanDirectory(_ url: URL, into found: inout [String: DiscoveredApp], depth: Int, maxDepth: Int) {
        guard depth <= maxDepth else { return }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for itemURL in contents {
            if itemURL.pathExtension == "app" {
                if let app = makeDiscoveredApp(from: itemURL) {
                    // Prefer the first one found (top-level /Applications takes priority).
                    if found[app.bundleId] == nil {
                        found[app.bundleId] = app
                    }
                }
            } else if depth < maxDepth {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: itemURL.path, isDirectory: &isDir), isDir.boolValue {
                    scanDirectory(itemURL, into: &found, depth: depth + 1, maxDepth: maxDepth)
                }
            }
        }
    }

    private func makeDiscoveredApp(from appURL: URL) -> DiscoveredApp? {
        guard let bundle = Bundle(url: appURL),
              let bundleId = bundle.bundleIdentifier else {
            return nil
        }

        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? appURL.deletingPathExtension().lastPathComponent

        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 64, height: 64)

        return DiscoveredApp(id: bundleId, name: name, bundleId: bundleId, icon: icon)
    }
}
