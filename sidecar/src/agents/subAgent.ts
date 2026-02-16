/**
 * Sub-agent tool — lets the main Flux agent delegate tasks to specialized child agents.
 *
 * Each sub-agent is a fresh pi-mono Agent instance with its own system prompt, model,
 * and (optionally) a filtered subset of tools. The sub-agent runs to completion and
 * its full response is returned as the tool result.
 */
import { Agent, type AgentTool } from '@mariozechner/pi-agent-core';
import { getModel, getProviders } from '@mariozechner/pi-ai';
import { Type } from '@sinclair/typebox';
import type { AgentProfile } from './types.js';
import type { ToolDefinition } from '../tools/types.js';
import { createLogger } from '../logger.js';

const log = createLogger('sub-agent');

/** Callback to send sub-agent lifecycle events to the Swift client. */
export interface SubAgentNotifier {
  onStart(toolUseId: string, agentId: string, agentName: string): void;
  onToolUse(toolUseId: string, subToolName: string, status: 'start' | 'complete'): void;
  onComplete(toolUseId: string, resultPreview: string): void;
}

interface SubAgentToolOptions {
  /** Available agent profiles for delegation. */
  profiles: AgentProfile[];
  /** Conversation ID for logging. */
  conversationId: string;
  /** Default model provider (inherited from parent agent). */
  defaultProvider: string;
  /** Default model ID (inherited from parent agent). */
  defaultModel: string;
  /** Base tool definitions that sub-agents can access (sidecar-local only). */
  availableToolDefs: ToolDefinition[];
  /** Converter: turn a ToolDefinition into an AgentTool with sidecar-local execute. */
  buildAgentTool: (def: ToolDefinition) => AgentTool;
  /** Notifier for sub-agent lifecycle events sent to the UI. */
  notifier: SubAgentNotifier;
}

function parseModelSpec(spec: string): { provider: string; model: string } | null {
  const trimmed = spec.trim();
  if (!trimmed) return null;
  const match = trimmed.match(/^([^:/]+)[:/](.+)$/);
  if (match && match[1] && match[2]) {
    return { provider: match[1].trim(), model: match[2].trim() };
  }
  return null;
}

/**
 * Create the `delegate_to_agent` tool for the main agent.
 */
export function createSubAgentTool(options: SubAgentToolOptions): AgentTool {
  const {
    profiles,
    conversationId,
    defaultProvider,
    defaultModel,
    availableToolDefs,
    buildAgentTool,
    notifier,
  } = options;

  const profileIds = profiles.map((p) => p.id);

  return {
    name: 'delegate_to_agent',
    label: 'Delegate to Agent',
    description: [
      'Delegate a task to a specialized sub-agent. The sub-agent runs independently with its own system prompt and returns a result.',
      '',
      'Available agents:',
      ...profiles.map((p) => `- "${p.id}": ${p.name}${p.description ? ` — ${p.description}` : ''}`),
    ].join('\n'),
    parameters: Type.Object({
      agentId: Type.String({
        description: `The agent profile ID to delegate to. Available: ${profileIds.join(', ')}`,
      }),
      task: Type.String({
        description: 'The task or prompt to send to the sub-agent.',
      }),
    }),
    execute: async (toolCallId, params, signal, onUpdate) => {
      const { agentId, task } = params as { agentId: string; task: string };
      const profile = profiles.find((p) => p.id === agentId);

      if (!profile) {
        throw new Error(
          `Unknown agent "${agentId}". Available agents: ${profileIds.join(', ')}`,
        );
      }

      log.info(`[${conversationId}] Delegating to sub-agent "${profile.name}" (${profile.id})`);

      // Notify UI that a sub-agent has started
      notifier.onStart(toolCallId, profile.id, profile.name);

      // Resolve model
      let provider = defaultProvider;
      let modelId = defaultModel;
      if (profile.model) {
        const parsed = parseModelSpec(profile.model);
        if (parsed) {
          provider = parsed.provider;
          modelId = parsed.model;
        }
      }

      let model;
      const validProviders = getProviders();
      if (!validProviders.includes(provider as any)) {
        log.warn(`Sub-agent "${profile.id}": unknown provider "${provider}", falling back to default`);
        model = getModel(defaultProvider as any, defaultModel);
      } else {
        try {
          model = getModel(provider as any, modelId);
        } catch {
          log.warn(`Sub-agent "${profile.id}": failed to get model ${provider}/${modelId}, falling back`);
          model = getModel(defaultProvider as any, defaultModel);
        }
      }

      // Build tools for the sub-agent (only whitelisted ones)
      const subAgentTools: AgentTool[] = [];
      if (profile.tools && profile.tools.length > 0) {
        const allowedNames = new Set(profile.tools);
        for (const def of availableToolDefs) {
          if (allowedNames.has(def.name)) {
            subAgentTools.push(buildAgentTool(def));
          }
        }
      }

      // Create the sub-agent
      const subAgent = new Agent({
        initialState: {
          systemPrompt: profile.systemPrompt,
          model,
          thinkingLevel: 'low',
          tools: subAgentTools,
          messages: [],
        },
      });

      // Collect response and forward events to UI
      let result = '';
      subAgent.subscribe((event) => {
        if (event.type === 'message_update' && event.assistantMessageEvent.type === 'text_delta') {
          result += event.assistantMessageEvent.delta;

          // Stream progress to the parent tool
          onUpdate?.({
            content: [{ type: 'text', text: result }],
            details: { agentId: profile.id, agentName: profile.name },
          });
        }

        // Forward sub-agent tool execution events to the UI
        if (event.type === 'tool_execution_start') {
          notifier.onToolUse(toolCallId, event.toolName, 'start');
        }
        if (event.type === 'tool_execution_end') {
          notifier.onToolUse(toolCallId, event.toolName, 'complete');
        }
      });

      // Abort sub-agent if parent aborts
      if (signal) {
        signal.addEventListener('abort', () => {
          subAgent.abort();
        }, { once: true });
      }

      try {
        await subAgent.prompt(task);
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        log.error(`Sub-agent "${profile.id}" error: ${msg}`);
        notifier.onComplete(toolCallId, `Error: ${msg}`);
        throw new Error(`Sub-agent "${profile.name}" failed: ${msg}`);
      }

      log.info(`[${conversationId}] Sub-agent "${profile.name}" completed (${result.length} chars)`);

      // Notify UI that sub-agent completed
      const preview = result.length > 200 ? result.slice(0, 200) + '…' : result;
      notifier.onComplete(toolCallId, preview || '(No output)');

      return {
        content: [{ type: 'text', text: result || '(Sub-agent produced no output)' }],
        details: { agentId: profile.id, agentName: profile.name, responseLength: result.length },
      };
    },
  };
}
