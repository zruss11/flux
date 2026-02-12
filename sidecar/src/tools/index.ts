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
    name: 'send_openclaw_message',
    description:
      'Send a message through OpenClaw. Supports Slack, Discord, Telegram, and other configured OpenClaw channels.',
    input_schema: {
      type: 'object',
      properties: {
        message: { type: 'string', description: 'Message text to send.' },
        channel: {
          type: 'string',
          enum: [
            'telegram',
            'whatsapp',
            'discord',
            'googlechat',
            'slack',
            'signal',
            'imessage',
            'nostr',
            'msteams',
            'mattermost',
            'nextcloud-talk',
            'matrix',
            'bluebubbles',
            'line',
            'zalo',
            'zalouser',
            'tlon',
          ],
          description: 'Optional channel provider. If omitted, OpenClaw will use its default routing.',
        },
        target: {
          type: 'string',
          description: 'Optional destination identifier (for example channel ID, user ID, @username, or phone number).',
        },
        account: {
          type: 'string',
          description: 'Optional OpenClaw account id to route through when multiple accounts exist.',
        },
        threadId: {
          type: 'string',
          description: 'Optional thread/forum id (for example Telegram forum thread).',
        },
        replyTo: {
          type: 'string',
          description: 'Optional message id to reply to.',
        },
        silent: {
          type: 'boolean',
          description: 'Send without notification when supported (for example Telegram).',
        },
      },
      required: ['message'],
    },
  },
  {
    name: 'openclaw_channels_list',
    description:
      'List OpenClaw channels/accounts that are currently configured.',
    input_schema: {
      type: 'object',
      properties: {},
    },
  },
  {
    name: 'openclaw_status',
    description:
      'Inspect OpenClaw health and connector status.',
    input_schema: {
      type: 'object',
      properties: {
        deep: {
          type: 'boolean',
          description: 'Run deeper channel probes.',
        },
        timeoutMs: {
          type: 'number',
          description: 'Optional probe timeout in milliseconds.',
        },
      },
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
