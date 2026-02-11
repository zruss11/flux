import Foundation

enum SkillCategory: String, CaseIterable {
    case productivity = "Productivity"
    case devTools = "Dev Tools"
    case communication = "Communication"
    case media = "Media & Design"
}

struct SkillDependency {
    enum Kind: String {
        case brew
    }

    let kind: Kind
    let formula: String
    let bins: [String]
    var tap: String?
}

struct RecommendedSkill {
    let directoryName: String
    let displayName: String
    let description: String
    let skillMdContent: String
    let category: SkillCategory
    var requiredPermissions: Set<SkillPermission> = []
    var dependencies: [SkillDependency] = []
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
            description: "iMessage/SMS CLI for listing chats, history, watch, and sending",
            skillMdContent: """
            ---
            name: imsg
            description: iMessage/SMS CLI for listing chats, history, watch, and sending.
            ---

            # imsg Actions

            ## Overview

            Use `imsg` to read and send Messages.app iMessage/SMS on macOS.

            Requirements: Messages.app signed in, Full Disk Access for your terminal, and Automation permission to control Messages.app for sending.

            ## Inputs to collect

            - Recipient handle (phone/email) for `send`
            - `chatId` for history/watch (from `imsg chats --limit 10 --json`)
            - `text` and optional `file` path for sends

            ## Actions

            ### List chats

            ```bash
            imsg chats --limit 10 --json
            ```

            ### Fetch chat history

            ```bash
            imsg history --chat-id 1 --limit 20 --attachments --json
            ```

            ### Watch a chat

            ```bash
            imsg watch --chat-id 1 --attachments
            ```

            ### Send a message

            ```bash
            imsg send --to "+14155551212" --text "hi" --file /path/pic.jpg
            ```

            ## Notes

            - `--service imessage|sms|auto` controls delivery.
            - Confirm recipient + message before sending.
            """,
            category: .communication,
            requiredPermissions: [.automation],
            dependencies: [
                SkillDependency(kind: .brew, formula: "steipete/tap/imsg", bins: ["imsg"])
            ]
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
            description: "Interact with GitHub using the gh CLI",
            skillMdContent: """
            ---
            name: GitHub
            description: Interact with GitHub using the `gh` CLI. Use `gh issue`, `gh pr`, `gh run`, and `gh api` for issues, PRs, CI runs, and advanced queries.
            ---

            # GitHub Skill

            Use the `gh` CLI to interact with GitHub. Always specify `--repo owner/repo` when not in a git directory, or use URLs directly.

            ## Pull Requests

            Check CI status on a PR:

            ```bash
            gh pr checks 55 --repo owner/repo
            ```

            List recent workflow runs:

            ```bash
            gh run list --repo owner/repo --limit 10
            ```

            View a run and see which steps failed:

            ```bash
            gh run view <run-id> --repo owner/repo
            ```

            View logs for failed steps only:

            ```bash
            gh run view <run-id> --repo owner/repo --log-failed
            ```

            ## API for Advanced Queries

            The `gh api` command is useful for accessing data not available through other subcommands.

            Get PR with specific fields:

            ```bash
            gh api repos/owner/repo/pulls/55 --jq '.title, .state, .user.login'
            ```

            ## JSON Output

            Most commands support `--json` for structured output. You can use `--jq` to filter:

            ```bash
            gh issue list --repo owner/repo --json number,title --jq '.[] | "\\(.number): \\(.title)"'
            ```
            """,
            category: .devTools,
            dependencies: [
                SkillDependency(kind: .brew, formula: "gh", bins: ["gh"])
            ]
        ),
        RecommendedSkill(
            directoryName: "spotify",
            displayName: "Spotify",
            description: "Terminal Spotify playback and search via spogo",
            skillMdContent: """
            ---
            name: Spotify
            description: Terminal Spotify playback/search via spogo.
            ---

            # spogo

            Use `spogo` for Spotify playback/search from the terminal.

            Requirements: Spotify Premium account and `spogo` installed.

            ## Setup

            Import cookies: `spogo auth import --browser chrome`

            ## Common CLI commands

            - Search: `spogo search track "query"`
            - Playback: `spogo play|pause|next|prev`
            - Devices: `spogo device list`, `spogo device set "<name|id>"`
            - Status: `spogo status`
            """,
            category: .media,
            dependencies: [
                SkillDependency(kind: .brew, formula: "spogo", bins: ["spogo"], tap: "steipete/tap")
            ]
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
            description: "Notion API for creating and managing pages, databases, and blocks",
            skillMdContent: """
            ---
            name: Notion
            description: Notion API for creating and managing pages, databases, and blocks.
            ---

            # Notion

            Use the Notion API to create/read/update pages, data sources (databases), and blocks.

            ## Setup

            1. Create an integration at https://notion.so/my-integrations
            2. Copy the API key (starts with `ntn_` or `secret_`)
            3. Store it:

            ```bash
            mkdir -p ~/.config/notion
            echo "ntn_your_key_here" > ~/.config/notion/api_key
            ```

            4. Share target pages/databases with your integration (click "..." > "Connect to" > your integration name)

            ## API Basics

            All requests need:

            ```bash
            NOTION_KEY=$(cat ~/.config/notion/api_key)
            curl -X GET "https://api.notion.com/v1/..." \\
              -H "Authorization: Bearer $NOTION_KEY" \\
              -H "Notion-Version: 2025-09-03" \\
              -H "Content-Type: application/json"
            ```

            ## Common Operations

            **Search for pages and data sources:**

            ```bash
            curl -X POST "https://api.notion.com/v1/search" \\
              -H "Authorization: Bearer $NOTION_KEY" \\
              -H "Notion-Version: 2025-09-03" \\
              -H "Content-Type: application/json" \\
              -d '{"query": "page title"}'
            ```

            **Get page content (blocks):**

            ```bash
            curl "https://api.notion.com/v1/blocks/{page_id}/children" \\
              -H "Authorization: Bearer $NOTION_KEY" \\
              -H "Notion-Version: 2025-09-03"
            ```

            **Create page in a data source:**

            ```bash
            curl -X POST "https://api.notion.com/v1/pages" \\
              -H "Authorization: Bearer $NOTION_KEY" \\
              -H "Notion-Version: 2025-09-03" \\
              -H "Content-Type: application/json" \\
              -d '{"parent": {"database_id": "xxx"}, "properties": {"Name": {"title": [{"text": {"content": "New Item"}}]}}}'
            ```

            **Query a data source (database):**

            ```bash
            curl -X POST "https://api.notion.com/v1/data_sources/{data_source_id}/query" \\
              -H "Authorization: Bearer $NOTION_KEY" \\
              -H "Notion-Version: 2025-09-03" \\
              -H "Content-Type: application/json" \\
              -d '{"filter": {"property": "Status", "select": {"equals": "Active"}}}'
            ```

            ## Notes

            - Page/database IDs are UUIDs (with or without dashes)
            - Rate limit: ~3 requests/second average
            - The `Notion-Version` header is required (use `2025-09-03`)
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
            description: "Send, read, react, and manage pins in Slack channels and DMs",
            skillMdContent: """
            ---
            name: Slack
            description: Use to control Slack — react, pin/unpin, send/edit/delete messages, and fetch member info in Slack channels or DMs.
            ---

            # Slack Actions

            ## Overview

            Use `slack` to react, manage pins, send/edit/delete messages, and fetch member info. The tool uses the bot token configured for Flux.

            ## Inputs to collect

            - `channelId` and `messageId` (Slack message timestamp, e.g. `1712023032.1234`).
            - For reactions, an `emoji` (Unicode or `:name:`).
            - For message sends, a `to` target (`channel:<id>` or `user:<id>`) and `content`.

            ## Actions

            ### React to a message

            ```json
            {"action": "react", "channelId": "C123", "messageId": "1712023032.1234", "emoji": "check"}
            ```

            ### Send a message

            ```json
            {"action": "sendMessage", "to": "channel:C123", "content": "Hello from Flux"}
            ```

            ### Read recent messages

            ```json
            {"action": "readMessages", "channelId": "C123", "limit": 20}
            ```

            ### Pin a message

            ```json
            {"action": "pinMessage", "channelId": "C123", "messageId": "1712023032.1234"}
            ```

            ### Member info

            ```json
            {"action": "memberInfo", "userId": "U123"}
            ```
            """,
            category: .communication
        ),
        RecommendedSkill(
            directoryName: "discord",
            displayName: "Discord",
            description: "Send messages, react, manage threads, polls, and channels in Discord",
            skillMdContent: """
            ---
            name: Discord
            description: Control Discord — send messages, react, manage threads/pins/search, create polls, and handle moderation in Discord channels or DMs.
            ---

            # Discord Actions

            ## Overview

            Use `discord` to manage messages, reactions, threads, polls, and moderation. The tool uses the bot token configured for Flux.

            ## Inputs to collect

            - For reactions: `channelId`, `messageId`, and an `emoji`.
            - For sendMessage: a `to` target (`channel:<id>` or `user:<id>`). Optional `content` text.
            - Polls need a `question` plus 2-10 `answers`.

            ## Actions

            ### React to a message

            ```json
            {"action": "react", "channelId": "123", "messageId": "456", "emoji": "check"}
            ```

            ### Send a message

            ```json
            {"action": "sendMessage", "to": "channel:123", "content": "Hello from Flux"}
            ```

            ### Read recent messages

            ```json
            {"action": "readMessages", "channelId": "123", "limit": 20}
            ```

            ### Create a poll

            ```json
            {"action": "poll", "to": "channel:123", "question": "Lunch?", "answers": ["Pizza", "Sushi", "Salad"], "durationHours": 24}
            ```

            ### Create a thread

            ```json
            {"action": "threadCreate", "channelId": "123", "name": "Bug triage", "messageId": "456"}
            ```

            ### Pin a message

            ```json
            {"action": "pinMessage", "channelId": "123", "messageId": "456"}
            ```

            ### Search messages

            ```json
            {"action": "searchMessages", "guildId": "999", "content": "release notes", "limit": 10}
            ```
            """,
            category: .communication
        ),
        RecommendedSkill(
            directoryName: "apple-notes",
            displayName: "Apple Notes",
            description: "Manage Apple Notes via the memo CLI (create, view, edit, delete, search)",
            skillMdContent: """
            ---
            name: Apple Notes
            description: Manage Apple Notes via the `memo` CLI on macOS (create, view, edit, delete, search, move, and export notes).
            ---

            # Apple Notes CLI

            Use `memo notes` to manage Apple Notes directly from the terminal. Create, view, edit, delete, search, move notes between folders, and export to HTML/Markdown.

            ## Setup

            - macOS-only; if prompted, grant Automation access to Notes.app.

            ## View Notes

            - List all notes: `memo notes`
            - Filter by folder: `memo notes -f "Folder Name"`
            - Search notes (fuzzy): `memo notes -s "query"`

            ## Create Notes

            - Add a new note: `memo notes -a`
            - Quick add with title: `memo notes -a "Note Title"`

            ## Edit Notes

            - Edit existing note: `memo notes -e`

            ## Delete Notes

            - Delete a note: `memo notes -d`

            ## Move Notes

            - Move note to folder: `memo notes -m`

            ## Export Notes

            - Export to HTML/Markdown: `memo notes -ex`

            ## Limitations

            - Cannot edit notes containing images or attachments.
            - Requires Apple Notes.app to be accessible.
            """,
            category: .productivity,
            requiredPermissions: [.automation],
            dependencies: [
                SkillDependency(kind: .brew, formula: "antoniorodr/memo/memo", bins: ["memo"])
            ]
        ),
        RecommendedSkill(
            directoryName: "reminders",
            displayName: "Reminders",
            description: "Manage Apple Reminders via the remindctl CLI (list, add, edit, complete, delete)",
            skillMdContent: """
            ---
            name: Reminders
            description: Manage Apple Reminders via the `remindctl` CLI on macOS (list, add, edit, complete, delete). Supports lists, date filters, and JSON/plain output.
            ---

            # Apple Reminders CLI (remindctl)

            Use `remindctl` to manage Apple Reminders directly from the terminal.

            ## Setup

            - macOS-only; grant Reminders permission when prompted.

            ## Permissions

            - Check status: `remindctl status`
            - Request access: `remindctl authorize`

            ## View Reminders

            - Default (today): `remindctl`
            - Today: `remindctl today`
            - Tomorrow: `remindctl tomorrow`
            - Week: `remindctl week`
            - Overdue: `remindctl overdue`
            - All: `remindctl all`
            - Specific date: `remindctl 2026-01-04`

            ## Manage Lists

            - List all lists: `remindctl list`
            - Show list: `remindctl list Work`
            - Create list: `remindctl list Projects --create`

            ## Create Reminders

            - Quick add: `remindctl add "Buy milk"`
            - With list + due: `remindctl add --title "Call mom" --list Personal --due tomorrow`

            ## Complete / Delete

            - Complete by id: `remindctl complete 1 2 3`
            - Delete by id: `remindctl delete 4A83 --force`

            ## Output Formats

            - JSON: `remindctl today --json`
            - Plain TSV: `remindctl today --plain`
            - Counts only: `remindctl today --quiet`

            ## Date Formats

            Accepted by `--due` and date filters: `today`, `tomorrow`, `yesterday`, `YYYY-MM-DD`, `YYYY-MM-DD HH:mm`, ISO 8601.
            """,
            category: .productivity,
            requiredPermissions: [.reminders],
            dependencies: [
                SkillDependency(kind: .brew, formula: "steipete/tap/remindctl", bins: ["remindctl"])
            ]
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
