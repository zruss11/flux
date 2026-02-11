import SwiftUI

struct Skill: Identifiable, Hashable {
    let id: UUID
    let name: String
    let directoryName: String
    let description: String?
    let icon: String      // SF Symbol name
    let color: Color
    let isInstalled: Bool
    var requiredPermissions: Set<SkillPermission> = []

    // MARK: - Icon Mapping

    static func iconForName(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("browser") || lower.contains("web") { return "globe" }
        if lower.contains("build") || lower.contains("xcode") { return "hammer.fill" }
        if lower.contains("release") || lower.contains("deploy") { return "arrow.up.circle.fill" }
        if lower.contains("test") || lower.contains("testflight") { return "checkmark.circle.fill" }
        if lower.contains("design") || lower.contains("ui") || lower.contains("ux") { return "paintbrush.fill" }
        if lower.contains("find") || lower.contains("search") || lower.contains("discover") { return "magnifyingglass" }
        if lower.contains("wiki") || lower.contains("doc") { return "book.fill" }
        if lower.contains("note") || lower.contains("napkin") { return "note.text" }
        if lower.contains("sign") || lower.contains("auth") { return "lock.fill" }
        if lower.contains("price") || lower.contains("pricing") { return "dollarsign.circle.fill" }
        if lower.contains("submit") || lower.contains("health") { return "heart.fill" }
        if lower.contains("metadata") || lower.contains("sync") { return "arrow.triangle.2.circlepath" }
        if lower.contains("cli") || lower.contains("shell") || lower.contains("command") { return "terminal.fill" }
        if lower.contains("react") || lower.contains("vue") || lower.contains("svelte") { return "chevron.left.forwardslash.chevron.right" }
        if lower.contains("video") || lower.contains("remotion") || lower.contains("animation") { return "film.fill" }
        if lower.contains("delegate") || lower.contains("delegation") { return "person.2.fill" }
        if lower.contains("resolve") { return "number.circle.fill" }
        if lower.contains("notariz") { return "checkmark.seal.fill" }
        if lower.contains("linear") { return "rectangle.connected.to.line.below" }
        if lower.contains("vercel") { return "triangle.fill" }
        if lower.contains("super") { return "star.fill" }
        if lower.contains("sentry") { return "exclamationmark.triangle.fill" }
        if lower.contains("imessage") || lower.contains("message") { return "message.fill" }
        if lower.contains("calendar") && lower.contains("google") { return "calendar.badge.clock" }
        if lower.contains("calendar") { return "calendar" }
        if lower.contains("github") { return "chevron.left.forwardslash.chevron.right" }
        if lower.contains("spotify") { return "music.note" }
        if lower.contains("gmail") { return "envelope.fill" }
        if lower.contains("figma") { return "paintbrush.pointed.fill" }
        if lower.contains("notion") { return "doc.richtext" }
        if lower.contains("todoist") || lower.contains("todo") { return "checklist" }
        if lower.contains("jira") { return "list.bullet.rectangle" }
        if lower.contains("slack") { return "number" }
        if lower.contains("discord") { return "bubble.left.and.bubble.right.fill" }
        if lower.contains("reminder") { return "bell.fill" }
        if lower.contains("terminal") { return "terminal.fill" }
        if lower.contains("raycast") { return "rays" }
        if lower.contains("sandbox") || lower.contains("codex") || lower.contains("coding agent") { return "cube.fill" }
        return "sparkle"
    }

    // MARK: - Color Mapping

    private static let palette: [Color] = [
        .blue, .green, .red, .purple, .orange, .yellow, .cyan, .mint,
        .pink, .indigo, .teal, .brown,
    ]

    static func colorForName(_ name: String) -> Color {
        // Stable hash (DJB2) so colors don't change across launches
        var hash: UInt64 = 5381
        for byte in name.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
        }
        return palette[Int(hash % UInt64(palette.count))]
    }
}
