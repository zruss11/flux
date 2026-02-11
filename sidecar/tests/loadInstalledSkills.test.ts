import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { loadInstalledSkills } from '../src/skills/loadInstalledSkills.js';

const TEST_SKILL_ID = '__vitest_skill__';

const testDir = path.dirname(fileURLToPath(import.meta.url));
const sidecarRoot = path.resolve(testDir, '..');
const repoRoot = path.resolve(sidecarRoot, '..');

describe('loadInstalledSkills', () => {
  let skillDir: string;

  beforeEach(async () => {
    skillDir = path.join(repoRoot, '.agents', 'skills', TEST_SKILL_ID);
    await fs.mkdir(path.join(skillDir, 'agents'), { recursive: true });

    await fs.writeFile(
      path.join(skillDir, 'SKILL.md'),
      [
        '---',
        'name: My Test Skill',
        'description: Test description',
        '---',
        '# My Test Skill',
        '',
        'Hello.',
      ].join('\n'),
      'utf8',
    );

    await fs.writeFile(
      path.join(skillDir, 'agents', 'openai.yaml'),
      [
        'interface:',
        '  default_prompt: "Be helpful"',
        'dependencies:',
        '  tools:',
        '    - type: mcp',
        '      value: test_server',
        '      url: http://localhost:9999',
        '      transport: stdio',
        '      description: Test MCP',
      ].join('\n'),
      'utf8',
    );
  });

  afterEach(async () => {
    if (skillDir) {
      await fs.rm(skillDir, { recursive: true, force: true });
    }
  });

  it('loads skill metadata and MCP dependencies', async () => {
    const skills = await loadInstalledSkills();
    const skill = skills.find((s) => s.id === TEST_SKILL_ID);

    expect(skill).toBeTruthy();
    expect(skill?.name).toBe('My Test Skill');
    expect(skill?.description).toBe('Test description');
    expect(skill?.defaultPrompt).toBe('Be helpful');
    expect(skill?.mcpDependencies).toEqual([
      {
        id: 'test_server',
        url: 'http://localhost:9999',
        transport: 'stdio',
        description: 'Test MCP',
      },
    ]);
  });
});
