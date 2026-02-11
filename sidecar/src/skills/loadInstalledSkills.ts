import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import YAML from 'yaml';
import type { InstalledSkill, SkillMcpDependency } from './types.js';

function getRepoRoot(): string {
  const here = path.dirname(fileURLToPath(import.meta.url)); // sidecar/src/skills
  const sidecarRoot = path.resolve(here, '..', '..'); // sidecar/
  return path.resolve(sidecarRoot, '..'); // repo root
}

async function findAncestorWithAgentsSkills(startDir: string): Promise<string | null> {
  let cur = path.resolve(startDir);
  // Prevent infinite loops on weird paths.
  for (let i = 0; i < 50; i++) {
    const skillsDir = path.join(cur, '.agents', 'skills');
    if (await fileExists(skillsDir)) return skillsDir;

    const parent = path.dirname(cur);
    if (parent === cur) break;
    cur = parent;
  }
  return null;
}

async function fileExists(p: string): Promise<boolean> {
  try {
    await fs.stat(p);
    return true;
  } catch {
    return false;
  }
}

function parseFrontmatter(md: string): Record<string, unknown> | null {
  if (!md.startsWith('---\n')) return null;
  const end = md.indexOf('\n---', 4);
  if (end === -1) return null;
  const fm = md.slice(4, end + 1); // include trailing \n for YAML parser friendliness
  try {
    const parsed = YAML.parse(fm);
    return parsed && typeof parsed === 'object' ? (parsed as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

type OpenAiAgentYaml = {
  interface?: {
    default_prompt?: string;
  };
  dependencies?: {
    tools?: Array<{
      type?: string;
      value?: string;
      description?: string;
      transport?: string;
      url?: string;
    }>;
  };
};

function parseSkillMcpDependencies(agentYaml: OpenAiAgentYaml): SkillMcpDependency[] {
  const deps = agentYaml.dependencies?.tools ?? [];
  const mcp: SkillMcpDependency[] = [];
  for (const d of deps) {
    if (d?.type !== 'mcp') continue;
    if (!d.value || !d.url) continue;
    mcp.push({
      id: d.value,
      url: d.url,
      transport: (d.transport ?? 'streamable_http') as SkillMcpDependency['transport'],
      description: d.description,
    });
  }
  return mcp;
}

async function loadSkillsFromRoot(skillsRoot: string): Promise<InstalledSkill[]> {
  if (!(await fileExists(skillsRoot))) return [];

  const dirents = await fs.readdir(skillsRoot, { withFileTypes: true });
  const skills: InstalledSkill[] = [];

  for (const ent of dirents) {
    if (!ent.isDirectory()) continue;
    const id = ent.name;
    const skillDir = path.join(skillsRoot, id);

    const skillMdPath = path.join(skillDir, 'SKILL.md');
    const openAiAgentYamlPath = path.join(skillDir, 'agents', 'openai.yaml');

    let name = id;
    let description: string | undefined;
    let defaultPrompt: string | undefined;
    let mcpDependencies: SkillMcpDependency[] = [];

    if (await fileExists(skillMdPath)) {
      const md = await fs.readFile(skillMdPath, 'utf8');
      const fm = parseFrontmatter(md);
      if (fm?.name && typeof fm.name === 'string') name = fm.name;
      if (fm?.description && typeof fm.description === 'string') description = fm.description;
    }

    if (await fileExists(openAiAgentYamlPath)) {
      try {
        const yamlText = await fs.readFile(openAiAgentYamlPath, 'utf8');
        const parsed = YAML.parse(yamlText) as OpenAiAgentYaml;
        defaultPrompt = parsed?.interface?.default_prompt;
        mcpDependencies = parseSkillMcpDependencies(parsed);
      } catch {
        // ignore invalid YAML
      }
    }

    skills.push({
      id,
      name,
      description,
      defaultPrompt,
      mcpDependencies,
    });
  }

  return skills;
}

export async function loadInstalledSkills(): Promise<InstalledSkill[]> {
  const repoRoot = getRepoRoot();

  // Project skills: prefer `.agents/skills` discovered near CWD (active project),
  // with a fallback to repo-local `.agents/skills` for dev.
  const cwdProjectSkills = await findAncestorWithAgentsSkills(process.cwd());
  const repoSkills = path.join(repoRoot, '.agents', 'skills');

  // Global skills: users can install skills into ~/.claude/skills (and some setups use ~/.agents/skills).
  const home = os.homedir();
  const globalClaudeSkills = path.join(home, '.claude', 'skills');
  const globalAgentsSkills = path.join(home, '.agents', 'skills');

  const roots = [
    cwdProjectSkills,
    repoSkills,
    globalClaudeSkills,
    globalAgentsSkills,
  ].filter((p): p is string => Boolean(p));

  const seenIds = new Set<string>();
  const out: InstalledSkill[] = [];

  for (const root of roots) {
    const loaded = await loadSkillsFromRoot(root);
    for (const s of loaded) {
      if (seenIds.has(s.id)) continue;
      seenIds.add(s.id);
      out.push(s);
    }
  }

  return out;
}
