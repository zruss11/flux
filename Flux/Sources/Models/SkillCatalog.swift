import Foundation

struct RecommendedSkill {
    let directoryName: String
    let displayName: String
    let description: String
    let skillMdContent: String
}

enum SkillCatalog {
    static let recommended: [RecommendedSkill] = [
        RecommendedSkill(
            directoryName: "linear",
            displayName: "Linear",
            description: "Manage issues, projects, and cycles in Linear",
            skillMdContent: """
            ---
            name: Linear
            description: Manage issues, projects, and cycles in Linear
            ---
            # Linear

            Use the Linear MCP integration to create, update, and search issues, projects, and cycles.

            ## Capabilities
            - Create and update issues
            - Search and filter issues
            - Manage projects and cycles
            - View team workflows
            """
        ),
        RecommendedSkill(
            directoryName: "sentry",
            displayName: "Sentry",
            description: "Monitor errors and performance with Sentry",
            skillMdContent: """
            ---
            name: Sentry
            description: Monitor errors and performance with Sentry
            ---
            # Sentry

            Monitor application errors and performance using the Sentry integration.

            ## Capabilities
            - View recent error events
            - Inspect issue details and stack traces
            - Check release health
            - Monitor performance metrics
            """
        ),
        RecommendedSkill(
            directoryName: "imessage",
            displayName: "iMessage",
            description: "Send and read iMessages",
            skillMdContent: """
            ---
            name: iMessage
            description: Send and read iMessages
            ---
            # iMessage

            Send and read iMessages using macOS automation.

            ## Capabilities
            - Send messages to contacts
            - Read recent conversations
            - Search message history
            """
        ),
        RecommendedSkill(
            directoryName: "calendar",
            displayName: "Calendar",
            description: "View and manage macOS Calendar events",
            skillMdContent: """
            ---
            name: Calendar
            description: View and manage macOS Calendar events
            ---
            # Calendar

            View and manage events in macOS Calendar.

            ## Capabilities
            - View upcoming events
            - Create new events
            - Check availability
            - Manage reminders
            """
        ),
        RecommendedSkill(
            directoryName: "github",
            displayName: "GitHub",
            description: "Manage repos, PRs, and issues on GitHub",
            skillMdContent: """
            ---
            name: GitHub
            description: Manage repos, PRs, and issues on GitHub
            ---
            # GitHub

            Manage repositories, pull requests, and issues on GitHub.

            ## Capabilities
            - Create and review pull requests
            - Manage issues and labels
            - Browse repository contents
            - View CI/CD status
            """
        ),
        RecommendedSkill(
            directoryName: "spotify",
            displayName: "Spotify",
            description: "Control Spotify playback and browse music",
            skillMdContent: """
            ---
            name: Spotify
            description: Control Spotify playback and browse music
            ---
            # Spotify

            Control Spotify playback and browse music on macOS.

            ## Capabilities
            - Play, pause, and skip tracks
            - Search for songs and artists
            - Manage playlists
            - View currently playing
            """
        ),
        RecommendedSkill(
            directoryName: "gmail",
            displayName: "Gmail",
            description: "Read and compose emails with Gmail",
            skillMdContent: """
            ---
            name: Gmail
            description: Read and compose emails with Gmail
            ---
            # Gmail

            Read and compose emails using Gmail integration.

            ## Capabilities
            - Read inbox and search emails
            - Compose and send emails
            - Manage labels and filters
            - View email threads
            """
        ),
        RecommendedSkill(
            directoryName: "google-calendar",
            displayName: "Google Calendar",
            description: "Manage Google Calendar events and schedules",
            skillMdContent: """
            ---
            name: Google Calendar
            description: Manage Google Calendar events and schedules
            ---
            # Google Calendar

            Manage events and schedules in Google Calendar.

            ## Capabilities
            - View upcoming events
            - Create and edit events
            - Check availability across calendars
            - Manage calendar invitations
            """
        ),
        RecommendedSkill(
            directoryName: "figma",
            displayName: "Figma",
            description: "Access and inspect Figma designs",
            skillMdContent: """
            ---
            name: Figma
            description: Access and inspect Figma designs
            ---
            # Figma

            Access and inspect designs in Figma.

            ## Capabilities
            - Browse files and projects
            - Inspect component properties
            - Extract design tokens
            - View design specifications
            """
        ),
    ]
}
