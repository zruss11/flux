import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import type { CompatibilityCallToolResult, Tool } from '@modelcontextprotocol/sdk/types.js';

import type { InstalledSkill } from '../skills/types.js';
import type { ToolDefinition } from '../tools/types.js';

type ServerConfig = {
  id: string;
  url: string;
  transport: 'streamable_http' | string;
  description?: string;
};

type ServerState = {
  config: ServerConfig;
  client: Client | null;
  transport: StreamableHTTPClientTransport | null;
  tools: Tool[] | null;
  toolsFetchedAtMs: number;
  lastError: string | null;
};

const TOOLS_CACHE_TTL_MS = 5 * 60 * 1000;

function envTokenForServer(serverId: string): string | undefined {
  const upper = serverId.toUpperCase();
  return (
    process.env[`MCP_${upper}_TOKEN`] ||
    process.env[`${upper}_MCP_TOKEN`] ||
    process.env[`${upper}_TOKEN`] ||
    undefined
  );
}

function toAnthropicToolName(serverId: string, mcpToolName: string): string {
  // Keep this stable; Swift side uses different naming.
  return `${serverId}__${mcpToolName}`;
}

function mcpToolToAnthropicTool(serverId: string, tool: Tool): ToolDefinition {
  const schema = (tool as any).inputSchema ?? { type: 'object', properties: {} };
  const properties = (schema && typeof schema === 'object' && (schema as any).properties) || {};
  const required = (schema && typeof schema === 'object' && (schema as any).required) || undefined;

  return {
    name: toAnthropicToolName(serverId, tool.name),
    description: tool.description ?? `${serverId} MCP tool: ${tool.name}`,
    input_schema: {
      type: 'object',
      properties: properties as Record<string, unknown>,
      required: Array.isArray(required) ? (required as string[]) : undefined,
    },
  };
}

export class McpManager {
  private servers = new Map<string, ServerState>();
  private authTokens = new Map<string, string>();

  hasAuthToken(serverId: string): boolean {
    const overridden = this.authTokens.get(serverId);
    if (overridden !== undefined) return overridden.length > 0;
    return Boolean(envTokenForServer(serverId));
  }

  async setAuthToken(serverId: string, token: string): Promise<void> {
    this.authTokens.set(serverId, token);

    const state = this.servers.get(serverId);
    if (!state) return;

    // Drop cached tools and reconnect on next call with the new token.
    state.tools = null;
    state.toolsFetchedAtMs = 0;

    const transport = state.transport;
    state.client = null;
    state.transport = null;

    if (transport) {
      try {
        await transport.close();
      } catch {
        // ignore
      }
    }
  }

  registerFromSkills(skills: InstalledSkill[]): void {
    for (const skill of skills) {
      for (const dep of skill.mcpDependencies) {
        const id = dep.id;
        if (this.servers.has(id)) continue;
        this.servers.set(id, {
          config: {
            id,
            url: dep.url,
            transport: dep.transport,
            description: dep.description,
          },
          client: null,
          transport: null,
          tools: null,
          toolsFetchedAtMs: 0,
          lastError: null,
        });
      }
    }
  }

  hasServer(serverId: string): boolean {
    return this.servers.has(serverId);
  }

  listServerIds(): string[] {
    return Array.from(this.servers.keys());
  }

  getLastError(serverId: string): string | null {
    return this.servers.get(serverId)?.lastError ?? null;
  }

  async listTools(serverId: string): Promise<Tool[]> {
    const state = this.servers.get(serverId);
    if (!state) throw new Error(`Unknown MCP server: ${serverId}`);

    const now = Date.now();
    if (state.tools && now - state.toolsFetchedAtMs < TOOLS_CACHE_TTL_MS) {
      return state.tools;
    }

    await this.ensureConnected(serverId);
    if (!state.client) throw new Error(`MCP client not available for ${serverId}`);

    try {
      const res = await state.client.listTools();
      state.tools = res.tools as Tool[];
      state.toolsFetchedAtMs = now;
      state.lastError = null;
      return state.tools;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      state.lastError = msg;
      throw e;
    }
  }

  async callTool(
    serverId: string,
    toolName: string,
    args: Record<string, unknown>,
  ): Promise<CompatibilityCallToolResult> {
    const state = this.servers.get(serverId);
    if (!state) throw new Error(`Unknown MCP server: ${serverId}`);
    await this.ensureConnected(serverId);
    if (!state.client) throw new Error(`MCP client not available for ${serverId}`);

    try {
      const res = await state.client.callTool({ name: toolName, arguments: args });
      state.lastError = null;
      return res;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      state.lastError = msg;
      throw e;
    }
  }

  async getAnthropicTools(serverId: string): Promise<ToolDefinition[]> {
    const tools = await this.listTools(serverId);
    return tools.map((t) => mcpToolToAnthropicTool(serverId, t));
  }

  parseAnthropicToolName(name: string): { serverId: string; mcpToolName: string } | null {
    const idx = name.indexOf('__');
    if (idx <= 0) return null;
    const serverId = name.slice(0, idx);
    const mcpToolName = name.slice(idx + 2);
    if (!serverId || !mcpToolName) return null;
    if (!this.servers.has(serverId)) return null;
    return { serverId, mcpToolName };
  }

  private async ensureConnected(serverId: string): Promise<void> {
    const state = this.servers.get(serverId);
    if (!state) throw new Error(`Unknown MCP server: ${serverId}`);
    if (state.config.transport !== 'streamable_http') {
      throw new Error(`Unsupported MCP transport for ${serverId}: ${state.config.transport}`);
    }

    if (state.client && state.transport) return;

    const token = this.authTokens.get(serverId) ?? envTokenForServer(serverId);
    const headers: Record<string, string> = {};
    if (token) headers['Authorization'] = `Bearer ${token}`;

    const client = new Client({ name: 'flux-sidecar', version: '1.0.0' });
    const transport = new StreamableHTTPClientTransport(new URL(state.config.url), {
      requestInit: { headers },
    });

    client.onerror = (err) => {
      state.lastError = err instanceof Error ? err.message : String(err);
    };

    try {
      await client.connect(transport);
      state.client = client;
      state.transport = transport;
      state.lastError = null;
    } catch (e) {
      state.lastError = e instanceof Error ? e.message : String(e);
      try {
        await transport.close();
      } catch {
        // ignore
      }
      throw e;
    }
  }
}
