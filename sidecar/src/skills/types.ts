export interface SkillMcpDependency {
  id: string;
  url: string;
  transport: 'streamable_http' | 'sse' | 'stdio' | string;
  description?: string;
}

export interface InstalledSkill {
  // Directory name (skill "id") used for stable referencing across sources.
  id: string;
  name: string;
  description?: string;
  /** Absolute path to the SKILL.md file for on-demand loading. */
  skillPath: string;
  defaultPrompt?: string;
  mcpDependencies: SkillMcpDependency[];
}
