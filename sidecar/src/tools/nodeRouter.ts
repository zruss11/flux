import type { CompatibilityCallToolResult, Tool } from '@modelcontextprotocol/sdk/types.js';
import type { McpManager } from '../mcp/manager.js';
import { MEMORY_TOOL_NAME, executeMemoryCommand } from './memory.js';

function callToolResultToText(result: CompatibilityCallToolResult): string {
  const blocks = (result as any).content as Array<any> | undefined;
  const textParts: string[] = [];

  if (Array.isArray(blocks)) {
    for (const b of blocks) {
      if (b && typeof b === 'object' && b.type === 'text' && typeof b.text === 'string') {
        textParts.push(b.text);
      }
    }
  }

  const summary = textParts.join('\n').trim();
  const payload = {
    isError: Boolean((result as any).isError),
    text: summary || null,
    content: blocks ?? null,
    // Some older servers return { toolResult: ... } rather than { content: [...] }.
    toolResult: (result as any).toolResult ?? null,
    structuredContent: (result as any).structuredContent ?? null,
  };

  return JSON.stringify(payload, null, 2);
}

export function isNodeTool(toolName: string, mcp: McpManager): boolean {
  if (toolName === MEMORY_TOOL_NAME) return true;
  if (toolName === 'linear__setup') return true;
  if (toolName === 'linear__mcp_list_tools') return true;
  return mcp.parseAnthropicToolName(toolName) !== null;
}

export async function executeNodeTool(
  toolName: string,
  input: Record<string, unknown>,
  mcp: McpManager,
): Promise<string> {
  if (toolName === MEMORY_TOOL_NAME) {
    return executeMemoryCommand(input);
  }

  if (toolName === 'linear__setup') {
    return [
      'Linear tools are available via the Linear MCP server, but require an access token.',
      '',
      'Set one of these environment variables for the sidecar process:',
      '- `MCP_LINEAR_TOKEN` (preferred)',
      '- `LINEAR_MCP_TOKEN`',
      '- `LINEAR_TOKEN`',
      '',
      'Then restart the sidecar so it can connect and expose `linear__*` tools.',
    ].join('\n');
  }

  if (toolName === 'linear__mcp_list_tools') {
    try {
      const tools = await mcp.listTools('linear');
      return JSON.stringify(
        tools.map((t: Tool) => ({ name: t.name, description: t.description ?? null })),
        null,
        2,
      );
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      const hint = mcp.getLastError('linear');
      return `Failed to list Linear MCP tools: ${msg}${hint ? `\nLast error: ${hint}` : ''}`;
    }
  }

  const parsed = mcp.parseAnthropicToolName(toolName);
  if (!parsed) {
    return `Unknown node tool: ${toolName}`;
  }

  try {
    const res = await mcp.callTool(parsed.serverId, parsed.mcpToolName, input ?? {});
    return callToolResultToText(res);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    const hint = mcp.getLastError(parsed.serverId);
    return `MCP tool call failed (${parsed.serverId}/${parsed.mcpToolName}): ${msg}${hint ? `\nLast error: ${hint}` : ''}`;
  }
}
