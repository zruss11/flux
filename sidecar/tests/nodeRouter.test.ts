import { describe, expect, it } from 'vitest';

import { executeNodeTool, isNodeTool } from '../src/tools/nodeRouter.js';

const makeMcp = (overrides: Partial<any> = {}) => ({
  parseAnthropicToolName: () => null,
  callTool: async () => ({ content: [] }),
  listTools: async () => [],
  getLastError: () => null,
  ...overrides,
});

describe('nodeRouter', () => {
  it('recognizes built-in tools', () => {
    const mcp = makeMcp();
    expect(isNodeTool('memory', mcp)).toBe(true);
    expect(isNodeTool('linear__setup', mcp)).toBe(true);
    expect(isNodeTool('linear__mcp_list_tools', mcp)).toBe(true);
  });

  it('executes the Linear setup helper', async () => {
    const mcp = makeMcp();
    const result = await executeNodeTool('linear__setup', {}, mcp);
    expect(result).toContain('Linear tools are available');
    expect(result).toContain('MCP_LINEAR_TOKEN');
  });

  it('returns MCP tool output as JSON text', async () => {
    const mcp = makeMcp({
      parseAnthropicToolName: () => ({ serverId: 'test', mcpToolName: 'ping' }),
      callTool: async () => ({
        content: [
          { type: 'text', text: 'pong' },
          { type: 'text', text: 'ok' },
        ],
      }),
    });

    const result = await executeNodeTool('test__ping', { hello: 'world' }, mcp);
    const parsed = JSON.parse(result) as { text: string | null };
    expect(parsed.text).toBe('pong\nok');
  });

  it('handles unknown tools', async () => {
    const mcp = makeMcp();
    const result = await executeNodeTool('unknown_tool', {}, mcp);
    expect(result).toContain('Unknown node tool');
  });
});
