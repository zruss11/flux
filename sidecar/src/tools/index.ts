import type { ToolDefinition } from './types.js';
import { McpManager } from '../mcp/manager.js';
import { loadInstalledSkills } from '../skills/loadInstalledSkills.js';
import type { InstalledSkill } from '../skills/types.js';

export const baseTools: ToolDefinition[] = [
  {
    name: 'capture_screen',
    description:
      'Capture a screenshot of the main display or the frontmost window. When highlight_caret is true, a red rectangle is drawn around the currently focused UI element to show cursor position.',
    input_schema: {
      type: 'object',
      properties: {
        target: {
          type: 'string',
          enum: ['display', 'window'],
          description: 'Whether to capture the full display or just the frontmost window',
        },
        highlight_caret: {
          type: 'boolean',
          description:
            'When true, draws a red rectangle around the currently focused UI element (text field, button, etc.) on the screenshot.',
        },
      },
      required: ['target'],
    },
  },
  {
    name: 'read_ax_tree',
    description:
      'Read the accessibility tree of the frontmost window. Returns structured text content including buttons, labels, text fields, and other UI elements.',
    input_schema: {
      type: 'object',
      properties: {
        maxDepth: {
          type: 'number',
          description: 'Maximum depth to traverse the accessibility tree (default: 10)',
        },
      },
    },
  },
  {
    name: 'read_visible_windows',
    description:
      'Read accessibility context for visible windows across apps using AppleScript + System Events. Returns JSON with app/window metadata and sampled UI elements.',
    input_schema: {
      type: 'object',
      properties: {
        maxApps: {
          type: 'number',
          description: 'Maximum number of apps to scan (default: 10, max: 25)',
        },
        maxWindowsPerApp: {
          type: 'number',
          description: 'Maximum windows to sample per app (default: 4, max: 12)',
        },
        maxElementsPerWindow: {
          type: 'number',
          description: 'Maximum accessibility elements to sample per window (default: 60, max: 250)',
        },
        maxTextLength: {
          type: 'number',
          description: 'Maximum character length for each captured field (default: 280, max: 1000)',
        },
        includeMinimized: {
          type: 'boolean',
          description: 'Whether to include minimized windows (default: false)',
        },
      },
    },
  },
  {
    name: 'read_selected_text',
    description: 'Read the currently selected text from the frontmost application.',
    input_schema: {
      type: 'object',
      properties: {},
    },
  },
  {
    name: 'read_file',
    description:
      'Read a UTF-8 text file from disk. Supports optional line offset and limit for large files. Use this to load SKILL.md instructions before executing a skill.',
    input_schema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: 'Absolute or relative file path to read.',
        },
        offset: {
          type: 'number',
          description: '1-indexed line number to start reading from (default: 1).',
        },
        limit: {
          type: 'number',
          description: 'Maximum number of lines to read (default: 200, max: 2000).',
        },
      },
      required: ['path'],
    },
  },
  {
    name: 'run_shell_command',
    description:
      'Run a shell command on macOS and return stdout/stderr and exit code. Use this for CLI-based skills (for example imsg).',
    input_schema: {
      type: 'object',
      properties: {
        command: {
          type: 'string',
          description: 'Shell command to execute.',
        },
        workingDirectory: {
          type: 'string',
          description: 'Optional working directory for command execution.',
        },
        timeoutSeconds: {
          type: 'number',
          description: 'Optional timeout in seconds (default: 30, max: 120).',
        },
      },
      required: ['command'],
    },
  },

  {
    name: 'get_current_datetime',
    description:
      'Get the current date, time, timezone, and UTC offset. Use this whenever you need to know the current date or time instead of guessing.',
    input_schema: {
      type: 'object',
      properties: {},
    },
  },

  {
    name: 'create_automation',
    description:
      'Create a recurring automation. Provide the instruction prompt and a 5-field schedule expression (`minute hour day month weekday`, e.g. `0 9 * * 1-5`).',
    input_schema: {
      type: 'object',
      properties: {
        name: { type: 'string', description: 'Optional short name for the automation.' },
        prompt: { type: 'string', description: 'Instruction that should run each time the automation triggers.' },
        scheduleExpression: {
          type: 'string',
          description: '5-field schedule expression (`minute hour day month weekday`). Example: `0 9 * * 1-5`.',
        },
        timezone: {
          type: 'string',
          description: 'Optional IANA timezone (for example `America/Los_Angeles`). Defaults to local timezone.',
        },
      },
      required: ['prompt', 'scheduleExpression'],
    },
  },
  {
    name: 'list_automations',
    description: 'List all configured automations and their status/next run.',
    input_schema: {
      type: 'object',
      properties: {},
    },
  },
  {
    name: 'update_automation',
    description: 'Update an automation by id (name, prompt, schedule expression, or timezone).',
    input_schema: {
      type: 'object',
      properties: {
        id: { type: 'string', description: 'Automation id.' },
        name: { type: 'string', description: 'Optional new automation name.' },
        prompt: { type: 'string', description: 'Optional new instruction prompt.' },
        scheduleExpression: {
          type: 'string',
          description: 'Optional new 5-field schedule expression (`minute hour day month weekday`).',
        },
        timezone: {
          type: 'string',
          description: 'Optional new IANA timezone (for example `America/Los_Angeles`).',
        },
      },
      required: ['id'],
    },
  },
  {
    name: 'pause_automation',
    description: 'Pause an automation so it no longer runs on schedule.',
    input_schema: {
      type: 'object',
      properties: {
        id: { type: 'string', description: 'Automation id.' },
      },
      required: ['id'],
    },
  },
  {
    name: 'resume_automation',
    description: 'Resume a paused automation and schedule its next run.',
    input_schema: {
      type: 'object',
      properties: {
        id: { type: 'string', description: 'Automation id.' },
      },
      required: ['id'],
    },
  },
  {
    name: 'delete_automation',
    description: 'Delete an automation permanently.',
    input_schema: {
      type: 'object',
      properties: {
        id: { type: 'string', description: 'Automation id.' },
      },
      required: ['id'],
    },
  },
  {
    name: 'run_automation_now',
    description: 'Trigger an automation immediately without waiting for its next schedule.',
    input_schema: {
      type: 'object',
      properties: {
        id: { type: 'string', description: 'Automation id.' },
      },
      required: ['id'],
    },
  },
  {
    name: 'set_worktree',
    description:
      'Report the git worktree branch name back to the Flux UI after creating a worktree.',
    input_schema: {
      type: 'object',
      properties: {
        branchName: {
          type: 'string',
          description: 'The branch name of the created worktree',
        },
      },
      required: ['branchName'],
    },
  },
  {
    name: 'read_session_history',
    description:
      "Read the user's recent app session history. Shows which apps and windows the user has visited with timestamps. Useful for understanding what the user was working on or offering to resume context.",
    input_schema: {
      type: 'object',
      properties: {
        appName: {
          type: 'string',
          description: 'Optional filter by app name (case-insensitive partial match)',
        },
        limit: {
          type: 'number',
          description: 'Maximum number of sessions to return (default: 10)',
        },
      },
    },
  },
  {
    name: 'get_session_context_summary',
    description:
      "Get a human-readable text summary of the user's recent app activity. Use this to understand what the user has been doing across their desktop.",
    input_schema: {
      type: 'object',
      properties: {
        limit: {
          type: 'number',
          description: 'Maximum number of sessions to summarize (default: 10)',
        },
      },
    },
  },
  {
    name: 'read_clipboard_history',
    description:
      "Read the user's recent clipboard history (last 10 copied items). Each entry includes the copied text, timestamp, source application, and content type (plainText, url, or filePath). Use this when the user references something they copied earlier.",
    input_schema: {
      type: 'object',
      properties: {
        limit: {
          type: 'number',
          description: 'Maximum number of entries to return (default: 10, max: 10)',
        },
      },
    },
  },
  {
    name: 'check_github_status',
    description:
      'Check GitHub CI/CD status and notifications using the gh CLI. Returns recent CI failures and GitHub notifications. Requires the user to have authenticated with `gh auth login`.',
    input_schema: {
      type: 'object',
      properties: {
        repo: {
          type: 'string',
          description:
            'Optional owner/repo to filter results (e.g. "octocat/hello-world"). If omitted, returns results across all repos.',
        },
      },
    },
  },
  {
    name: 'manage_github_repos',
    description:
      'Manage the list of GitHub repos that Flux watches for CI failures and notifications. Use action "list" to see current repos, "add" to add a repo, or "remove" to remove one.',
    input_schema: {
      type: 'object',
      properties: {
        action: {
          type: 'string',
          enum: ['list', 'add', 'remove'],
          description: 'The action to perform: list, add, or remove.',
        },
        repo: {
          type: 'string',
          description:
            'The owner/repo to add or remove (e.g. "octocat/hello-world"). Required for add/remove.',
        },
      },
      required: ['action'],
    },
  },
  {
    name: 'calendar_search_events',
    description:
      'Search for events in macOS Calendar.app within a date range. Returns event details including id, title, start/end dates, location, notes, and calendar name.',
    input_schema: {
      type: 'object',
      properties: {
        startDate: {
          type: 'string',
          description: 'Start of the date range in ISO 8601 format (e.g. "2026-02-15T00:00:00-05:00").',
        },
        endDate: {
          type: 'string',
          description: 'End of the date range in ISO 8601 format (e.g. "2026-02-15T23:59:59-05:00").',
        },
        query: {
          type: 'string',
          description: 'Optional text to filter events by title (case-sensitive substring match).',
        },
        calendarName: {
          type: 'string',
          description: 'Optional calendar name to search within. If omitted, searches all calendars.',
        },
      },
      required: ['startDate', 'endDate'],
    },
  },
  {
    name: 'calendar_add_event',
    description:
      'Create a new event in macOS Calendar.app. Returns the new event ID on success.',
    input_schema: {
      type: 'object',
      properties: {
        title: {
          type: 'string',
          description: 'Event title/summary.',
        },
        startDate: {
          type: 'string',
          description: 'Event start in ISO 8601 format (e.g. "2026-02-16T14:00:00-05:00").',
        },
        endDate: {
          type: 'string',
          description: 'Event end in ISO 8601 format (e.g. "2026-02-16T15:00:00-05:00").',
        },
        notes: {
          type: 'string',
          description: 'Optional event notes/description.',
        },
        location: {
          type: 'string',
          description: 'Optional event location.',
        },
        calendarName: {
          type: 'string',
          description: 'Optional calendar name to add the event to. Uses default calendar if omitted.',
        },
        isAllDay: {
          type: 'boolean',
          description: 'Whether this is an all-day event (default: false).',
        },
      },
      required: ['title', 'startDate', 'endDate'],
    },
  },
  {
    name: 'calendar_edit_event',
    description:
      'Edit an existing event in macOS Calendar.app by its event ID. Only the fields you provide will be updated.',
    input_schema: {
      type: 'object',
      properties: {
        eventId: {
          type: 'string',
          description: 'The unique ID of the event to edit (returned by calendar_search_events or calendar_add_event).',
        },
        title: {
          type: 'string',
          description: 'New event title.',
        },
        startDate: {
          type: 'string',
          description: 'New start date/time in ISO 8601 format.',
        },
        endDate: {
          type: 'string',
          description: 'New end date/time in ISO 8601 format.',
        },
        notes: {
          type: 'string',
          description: 'New event notes/description.',
        },
        location: {
          type: 'string',
          description: 'New event location.',
        },
      },
      required: ['eventId'],
    },
  },
  {
    name: 'calendar_delete_event',
    description:
      'Delete an event from macOS Calendar.app by its event ID.',
    input_schema: {
      type: 'object',
      properties: {
        eventId: {
          type: 'string',
          description: 'The unique ID of the event to delete.',
        },
      },
      required: ['eventId'],
    },
  },
  {
    name: 'calendar_navigate_to_date',
    description:
      'Open macOS Calendar.app and navigate to a specific date, showing the day view.',
    input_schema: {
      type: 'object',
      properties: {
        date: {
          type: 'string',
          description: 'The date to navigate to in ISO 8601 format (e.g. "2026-03-01").',
        },
      },
      required: ['date'],
    },
  },
];

const mcp = new McpManager();
let installedSkills: InstalledSkill[] = [];
let skillsLoadedAtMs = 0;
const SKILLS_CACHE_TTL_MS = 2_000;

async function refreshSkillsIfNeeded(): Promise<void> {
  const now = Date.now();
  if (skillsLoadedAtMs > 0 && now - skillsLoadedAtMs < SKILLS_CACHE_TTL_MS) return;
  installedSkills = await loadInstalledSkills();
  mcp.registerFromSkills(installedSkills);
  skillsLoadedAtMs = now;
}

function linearHelperTools(): ToolDefinition[] {
  return [
    {
      name: 'linear__setup',
      description: 'Explain how to configure Linear MCP auth for Flux sidecar.',
      input_schema: { type: 'object', properties: {} },
    },
    {
      name: 'linear__mcp_list_tools',
      description: 'List available Linear MCP tools (requires Linear MCP auth).',
      input_schema: { type: 'object', properties: {} },
    },
  ];
}

export async function getToolDefinitions(): Promise<{
  tools: ToolDefinition[];
  mcp: McpManager;
  skills: InstalledSkill[];
}> {
  await refreshSkillsIfNeeded();

  const all: ToolDefinition[] = [...baseTools];

  // Skill-specific helpers (present even if MCP auth isn't configured yet).
  if (mcp.hasServer('linear')) {
    all.push(...linearHelperTools());

    // Best-effort: expose Linear MCP tools directly as `linear__<toolName>` if we can list them.
    if (mcp.hasAuthToken('linear')) {
      try {
        const linearTools = await mcp.getAnthropicTools('linear');
        all.push(...linearTools);
      } catch {
        // Keep only helper tools when unavailable.
      }
    }
  }

  return { tools: all, mcp, skills: installedSkills };
}
