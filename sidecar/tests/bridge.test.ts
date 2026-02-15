import { describe, it, expect } from 'vitest';
import { requiresApproval, collectCommandLikeInputValues } from '../src/bridge.js';

describe('bridge.ts', () => {
  describe('collectCommandLikeInputValues', () => {
    it('should collect values from command-like keys', () => {
      const input = {
        command: 'ls -la',
        other: 'value',
        args: ['-v', 'test'],
      };
      const values = collectCommandLikeInputValues(input);
      expect(values).toContain('ls -la');
      expect(values).toContain('-v test');
      expect(values).not.toContain('value');
    });

    it('should ignore empty values', () => {
      const input = {
        command: '   ',
        cmd: '',
      };
      const values = collectCommandLikeInputValues(input);
      expect(values).toHaveLength(0);
    });
  });

  describe('requiresApproval', () => {
    it('should allow benign tools without dangerous commands', () => {
      const result = requiresApproval('read_file', { path: '/tmp/test.txt' });
      expect(result).toBe(false);
    });

    it('should flag dangerous rm command', () => {
      const result = requiresApproval('run_shell_command', { command: 'rm -rf /' });
      expect(result).toBe(true);
    });

    it('should flag dangerous rm command in args', () => {
        const result = requiresApproval('run_shell_command', { args: ['rm', '-rf', '/'] });
        expect(result).toBe(true);
    });

    it('should flag sudo rm', () => {
      const result = requiresApproval('run_shell_command', { command: 'sudo rm /etc/hosts' });
      expect(result).toBe(true);
    });

    it('should flag git reset --hard', () => {
      const result = requiresApproval('run_shell_command', { command: 'git reset --hard HEAD' });
      expect(result).toBe(true);
    });

    it('should flag git clean -fd', () => {
      const result = requiresApproval('run_shell_command', { command: 'git clean -fd' });
      expect(result).toBe(true);
    });

    it('should not flag benign git commands', () => {
      const result = requiresApproval('run_shell_command', { command: 'git status' });
      expect(result).toBe(false);
    });

    it('should flag dangerous command in non-command tool if suspicious input found', () => {
        // Even if tool name doesn't sound like shell, if input has 'command' key with dangerous content
        const result = requiresApproval('some_tool', { command: 'rm -rf /' });
        expect(result).toBe(true);
    });

    it('should capture dangerous command in array input', () => {
        const result = requiresApproval('run_shell_command', { command: ['rm', '-rf', '/'] });
        expect(result).toBe(true);
    });

    it('should flag git stash drop', () => {
      expect(requiresApproval('run_shell_command', { command: 'git stash drop' })).toBe(true);
    });

    it('should flag git branch -D', () => {
      expect(requiresApproval('run_shell_command', { command: 'git branch -D feature' })).toBe(true);
    });

    it('should allow git push --force-with-lease', () => {
      expect(requiresApproval('run_shell_command', { 
        command: 'git push --force-with-lease' 
      })).toBe(false);
    });

    it('should flag git stash clear', () => {
      expect(requiresApproval('run_shell_command', { command: 'git stash clear' })).toBe(true);
    });
  });
});
