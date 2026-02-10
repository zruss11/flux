import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import YAML from 'yaml';
import type { InstalledSkill, SkillMcpDependency } from './types.js';

function getRepoRoot(): string {
  const here = path.dirname(fileURLToPath(import.meta.url)); // sidecar/src/skills
  const sidecarRoot = path.resolve(here, '..', '..'); // sidecar/
  return path.resolve(sidecarRoot, '..'); // repo root
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

export async function loadInstalledSkills(): Promise<InstalledSkill[]> {
  const repoRoot = getRepoRoot();
  const skillsRoot = path.join(repoRoot, '.agents', 'skills');

  if (!(await fileExists(skillsRoot))) return [];

  const dirents = await fs.readdir(skillsRoot, { withFileTypes: true });
  const skills: InstalledSkill[] = [];

  for (const ent of dirents) {
    if (!ent.isDirectory()) continue;
    const skillDir = path.join(skillsRoot, ent.name);

    const skillMdPath = path.join(skillDir, 'SKILL.md');
    const openAiAgentYamlPath = path.join(skillDir, 'agents', 'openai.yaml');

    let name = ent.name;
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
      name,
      description,
      defaultPrompt,
      mcpDependencies,
    });
  }

  return skills;
}

