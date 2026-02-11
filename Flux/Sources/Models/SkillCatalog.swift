import Foundation

enum SkillCategory: String, CaseIterable {
    case productivity = "Productivity"
    case devTools = "Dev Tools"
    case communication = "Communication"
    case media = "Media & Design"
}

struct RecommendedSkill {
    let directoryName: String
    let displayName: String
    let description: String
    let skillMdContent: String
    let category: SkillCategory
    var requiredPermissions: Set<SkillPermission> = []
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
            """,
            category: .devTools
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
            """,
            category: .devTools
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
            """,
            category: .communication,
            requiredPermissions: [.automation]
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
            """,
            category: .productivity,
            requiredPermissions: [.automation]
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
            """,
            category: .devTools
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
            """,
            category: .media,
            requiredPermissions: [.automation]
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
            """,
            category: .communication
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
            """,
            category: .productivity
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
            """,
            category: .media
        ),
        RecommendedSkill(
            directoryName: "notion",
            displayName: "Notion",
            description: "Read and manage Notion pages and databases",
            skillMdContent: """
            ---
            name: Notion
            description: Read and manage Notion pages and databases
            ---
            # Notion

            Read and manage pages and databases in Notion.

            ## Capabilities
            - Browse and search pages
            - Query and filter databases
            - Create and update pages
            - Manage page properties
            """,
            category: .productivity
        ),
        RecommendedSkill(
            directoryName: "todoist",
            displayName: "Todoist",
            description: "Create and manage tasks in Todoist",
            skillMdContent: """
            ---
            name: Todoist
            description: Create and manage tasks in Todoist
            ---
            # Todoist

            Create and manage tasks and projects in Todoist.

            ## Capabilities
            - Create and complete tasks
            - Organize tasks into projects
            - Set due dates and priorities
            - Search and filter tasks
            """,
            category: .productivity
        ),
        RecommendedSkill(
            directoryName: "jira",
            displayName: "Jira",
            description: "Track and manage Jira issues and sprints",
            skillMdContent: """
            ---
            name: Jira
            description: Track and manage Jira issues and sprints
            ---
            # Jira

            Track and manage issues, sprints, and projects in Jira.

            ## Capabilities
            - Create and update issues
            - View and manage sprints
            - Search with JQL queries
            - Track project progress
            """,
            category: .devTools
        ),
        RecommendedSkill(
            directoryName: "slack",
            displayName: "Slack",
            description: "Read and send Slack messages",
            skillMdContent: """
            ---
            name: Slack
            description: Read and send Slack messages
            ---
            # Slack

            Read and send messages in Slack channels and conversations.

            ## Capabilities
            - Read channel messages
            - Send and reply to messages
            - Search message history
            - List channels and users
            """,
            category: .communication
        ),
        RecommendedSkill(
            directoryName: "discord",
            displayName: "Discord",
            description: "Manage Discord channels and messages",
            skillMdContent: """
            ---
            name: Discord
            description: Manage Discord channels and messages
            ---
            # Discord

            Manage channels and messages in Discord servers.

            ## Capabilities
            - Read and send messages
            - Browse server channels
            - Manage channel settings
            - View server members
            """,
            category: .communication
        ),
        RecommendedSkill(
            directoryName: "apple-notes",
            displayName: "Apple Notes",
            description: "Create and search Apple Notes",
            skillMdContent: """
            ---
            name: Apple Notes
            description: Create and search Apple Notes
            ---
            # Apple Notes

            Create and search notes in Apple Notes using macOS automation.

            ## Capabilities
            - Create new notes
            - Search existing notes
            - Browse folders and tags
            - Edit note contents
            """,
            category: .productivity,
            requiredPermissions: [.automation]
        ),
        RecommendedSkill(
            directoryName: "reminders",
            displayName: "Reminders",
            description: "Manage macOS Reminders",
            skillMdContent: """
            ---
            name: Reminders
            description: Manage macOS Reminders
            ---
            # Reminders

            Manage reminders and lists in macOS Reminders.

            ## Capabilities
            - Create and complete reminders
            - Organize into lists
            - Set due dates and priorities
            - Search reminders
            """,
            category: .productivity,
            requiredPermissions: [.automation]
        ),
        RecommendedSkill(
            directoryName: "terminal",
            displayName: "Terminal",
            description: "Execute shell commands and scripts",
            skillMdContent: """
            ---
            name: Terminal
            description: Execute shell commands and scripts
            ---
            # Terminal

            Execute shell commands and scripts on macOS.

            ## Capabilities
            - Run shell commands
            - Execute scripts and pipelines
            - Read command output
            - Manage environment variables
            """,
            category: .devTools
        ),
        RecommendedSkill(
            directoryName: "xcode",
            displayName: "Xcode",
            description: "Build, test, and manage Xcode projects",
            skillMdContent: """
            ---
            name: Xcode
            description: Build, test, and manage Xcode projects
            ---
            # Xcode

            Build, test, and manage Xcode projects on macOS.

            ## Capabilities
            - Build and run projects
            - Run unit and UI tests
            - Manage schemes and targets
            - View build logs and errors
            """,
            category: .devTools
        ),
        RecommendedSkill(
            directoryName: "arc-browser",
            displayName: "Arc Browser",
            description: "Control and read Arc browser tabs",
            skillMdContent: """
            ---
            name: Arc Browser
            description: Control and read Arc browser tabs
            ---
            # Arc Browser

            Control and read tabs in Arc Browser using macOS automation.

            ## Capabilities
            - List and switch tabs
            - Read page contents
            - Open and close tabs
            - Manage bookmarks and spaces
            """,
            category: .productivity,
            requiredPermissions: [.automation]
        ),
        RecommendedSkill(
            directoryName: "raycast",
            displayName: "Raycast",
            description: "Trigger Raycast commands and extensions",
            skillMdContent: """
            ---
            name: Raycast
            description: Trigger Raycast commands and extensions
            ---
            # Raycast

            Trigger commands and extensions in Raycast.

            ## Capabilities
            - Run built-in commands
            - Trigger installed extensions
            - Execute quicklinks
            - Access clipboard history
            """,
            category: .productivity,
            requiredPermissions: [.automation]
        ),
    ]
}
