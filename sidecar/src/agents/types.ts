export interface AgentProfile {
  /** Directory name — stable identifier across sources. */
  id: string;
  /** Human-readable name from frontmatter. */
  name: string;
  /** One-line description from frontmatter. */
  description?: string;
  /** Optional model spec (e.g. "anthropic:claude-sonnet-4-20250514"). */
  model?: string;
  /** Tool name allowlist. Empty or omitted = no tools (pure reasoning). */
  tools?: string[];
  /** Markdown body after frontmatter — used as the sub-agent system prompt. */
  systemPrompt: string;
  /** Absolute path to the AGENT.md file. */
  profilePath: string;
}
