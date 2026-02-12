import type { ToolDefinition } from './types.js';
import { McpManager } from '../mcp/manager.js';
import { loadInstalledSkills } from '../skills/loadInstalledSkills.js';
import type { InstalledSkill } from '../skills/types.js';

export const baseTools: ToolDefinition[] = [
  {
    name: 'capture_screen',
    description:
      'Capture a screenshot of the main display or the frontmost window. Returns a base64-encoded image (JPEG/PNG depending on app implementation).',
    input_schema: {
      type: 'object',
      properties: {
        target: {
          type: 'string',
          enum: ['display', 'window'],
          description: 'Whether to capture the full display or just the frontmost window',
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
    name: 'execute_applescript',
    description: 'Execute an AppleScript command and return the result.',
    input_schema: {
      type: 'object',
      properties: {
        script: {
          type: 'string',
          description: 'The AppleScript code to execute',
        },
      },
      required: ['script'],
    },
  },
  {
    name: 'run_shell_command',
    description: 'Run a shell command via /bin/zsh and return the output.',
    input_schema: {
      type: 'object',
      properties: {
        command: {
          type: 'string',
          description: 'The shell command to execute',
        },
        timeout: {
          type: 'number',
          description: 'Timeout in seconds (default: 30)',
        },
      },
      required: ['command'],
    },
  },
  {
    name: 'send_slack_message',
    description:
      'Send a message to Slack using the configured Slack bot (requires Slack Bot Token + Channel ID in Flux Settings). For posting to public channels without inviting the bot, add the Slack scope chat:write.public.',
    input_schema: {
      type: 'object',
      properties: {
        text: { type: 'string', description: 'Message text to post' },
        channelId: {
          type: 'string',
          description: 'Optional override channel ID (e.g. C123...). Defaults to the configured Slack Channel ID.',
        },
        channel: {
          type: 'string',
          description: '[Deprecated] Alias for channelId.',
        },
      },
      required: ['text'],
    },
  },
  {
    name: 'send_discord_message',
    description:
      'Send a message to Discord using the configured Discord bot (requires Discord Bot Token + Channel ID in Flux Settings).',
    input_schema: {
      type: 'object',
      properties: {
        content: { type: 'string', description: 'Message content to send' },
        channelId: {
          type: 'string',
          description:
            'Optional override Discord channel ID. Defaults to the configured Discord Channel ID in Flux Settings.',
        },
      },
      required: ['content'],
    },
  },
  {
    name: 'send_telegram_message',
    description:
      'Send a message to Telegram using the configured Telegram bot (requires Telegram Bot Token + Telegram Chat ID in Flux Settings).',
    input_schema: {
      type: 'object',
      properties: {
        text: { type: 'string', description: 'Message text to send' },
        chatId: {
          type: 'string',
          description: 'Optional override chat ID. Defaults to the configured Telegram Chat ID.',
        },
      },
      required: ['text'],
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
