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
  defaultPrompt?: string;
  mcpDependencies: SkillMcpDependency[];
}
