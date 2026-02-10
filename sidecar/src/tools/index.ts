export interface ToolDefinition {
  name: string;
  description: string;
  input_schema: {
    type: 'object';
    properties: Record<string, unknown>;
    required?: string[];
  };
}

export const tools: ToolDefinition[] = [
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
];
