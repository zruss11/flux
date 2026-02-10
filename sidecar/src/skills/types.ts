export interface SkillMcpDependency {
  id: string;
  url: string;
  transport: 'streamable_http' | 'sse' | 'stdio' | string;
  description?: string;
}

export interface InstalledSkill {
  name: string;
  description?: string;
  defaultPrompt?: string;
  mcpDependencies: SkillMcpDependency[];
}

