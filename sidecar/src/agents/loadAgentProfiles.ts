import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import YAML from 'yaml';
import type { AgentProfile } from './types.js';

async function fileExists(p: string): Promise<boolean> {
  try {
    await fs.stat(p);
    return true;
  } catch {
    return false;
  }
}

async function findAncestorDir(startDir: string, segments: string[]): Promise<string | null> {
  let cur = path.resolve(startDir);
  for (let i = 0; i < 50; i++) {
    const target = path.join(cur, ...segments);
    if (await fileExists(target)) return target;
    const parent = path.dirname(cur);
    if (parent === cur) break;
    cur = parent;
  }
  return null;
}

function parseFrontmatter(md: string): { meta: Record<string, unknown> | null; body: string } {
  if (!md.startsWith('---\n')) return { meta: null, body: md };
  const end = md.indexOf('\n---', 4);
  if (end === -1) return { meta: null, body: md };
  const fmBlock = md.slice(4, end + 1);
  const body = md.slice(end + 4).trim();
  try {
    const parsed = YAML.parse(fmBlock);
    return {
      meta: parsed && typeof parsed === 'object' ? (parsed as Record<string, unknown>) : null,
      body,
    };
  } catch {
    return { meta: null, body: md };
  }
}

async function loadProfilesFromRoot(agentsRoot: string): Promise<AgentProfile[]> {
  if (!(await fileExists(agentsRoot))) return [];

  const dirents = await fs.readdir(agentsRoot, { withFileTypes: true });
  const profiles: AgentProfile[] = [];

  for (const ent of dirents) {
    if (!ent.isDirectory()) continue;
    const id = ent.name;
    const agentDir = path.join(agentsRoot, id);
    const agentMdPath = path.join(agentDir, 'AGENT.md');

    if (!(await fileExists(agentMdPath))) continue;

    const md = await fs.readFile(agentMdPath, 'utf8');
    const { meta, body } = parseFrontmatter(md);

    const name = (meta?.name && typeof meta.name === 'string') ? meta.name : id;
    const description = (meta?.description && typeof meta.description === 'string') ? meta.description : undefined;
    const model = (meta?.model && typeof meta.model === 'string') ? meta.model : undefined;

    let tools: string[] | undefined;
    if (Array.isArray(meta?.tools)) {
      tools = (meta.tools as unknown[]).filter((t): t is string => typeof t === 'string');
    }

    profiles.push({
      id,
      name,
      description,
      model,
      tools,
      systemPrompt: body,
      profilePath: agentMdPath,
    });
  }

  return profiles;
}

/**
 * Discover and load agent profiles from standard locations.
 *
 * Search order (first-found-wins per id):
 * 1. `.agents/agents/` — project-local (ancestor walk from CWD)
 * 2. `.pi/agents/` — pi-convention project (ancestor walk from CWD)
 * 3. `~/.agents/agents/` — global user agents
 * 4. `~/.pi/agent/agents/` — global pi agents
 */
export async function loadAgentProfiles(): Promise<AgentProfile[]> {
  const cwdAgents = await findAncestorDir(process.cwd(), ['.agents', 'agents']);
  const cwdPiAgents = await findAncestorDir(process.cwd(), ['.pi', 'agents']);

  const home = os.homedir();
  const globalAgents = path.join(home, '.agents', 'agents');
  const globalPiAgents = path.join(home, '.pi', 'agent', 'agents');

  const roots = [
    cwdAgents,
    cwdPiAgents,
    globalAgents,
    globalPiAgents,
  ]
    .filter((p): p is string => Boolean(p))
    .filter((p, i, arr) => arr.indexOf(p) === i);

  const seenIds = new Set<string>();
  const out: AgentProfile[] = [];

  for (const root of roots) {
    const loaded = await loadProfilesFromRoot(root);
    for (const profile of loaded) {
      if (seenIds.has(profile.id)) continue;
      seenIds.add(profile.id);
      out.push(profile);
    }
  }

  return out;
}
