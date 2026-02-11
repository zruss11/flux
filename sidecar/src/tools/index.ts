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
