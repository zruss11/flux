import { describe, it, expect } from 'vitest';
import { parseImageToolResult, toolResultPreview } from '../src/bridge.js';

describe('image_parsing', () => {
  describe('parseImageToolResult', () => {
    it('should parse data URL with base64 prefix', () => {
      const input = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
      const result = parseImageToolResult(input);
      expect(result).not.toBeNull();
      expect(result?.mediaType).toBe('image/png');
      expect(result?.data).toBe('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
    });

    it('should parse raw base64 starting with iVBOR (PNG)', () => {
      const input = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
      const result = parseImageToolResult(input);
      expect(result).not.toBeNull();
      expect(result?.mediaType).toBe('image/png');
      expect(result?.data).toBe(input);
    });

    it('should parse raw base64 starting with /9j/ (JPEG)', () => {
      const input = '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9k=';
      const result = parseImageToolResult(input);
      expect(result).not.toBeNull();
      expect(result?.mediaType).toBe('image/jpeg');
      expect(result?.data).toBe(input);
    });

    it('should return null for non-image strings', () => {
      expect(parseImageToolResult('some random text')).toBeNull();
      expect(parseImageToolResult('{"json": "value"}')).toBeNull();
    });
  });

  describe('toolResultPreview', () => {
    it('should return truncated text for non-capture_screen tools', () => {
      const longText = 'a'.repeat(300);
      const preview = toolResultPreview('read_file', longText);
      expect(preview.length).toBe(200);
      expect(preview).toBe('a'.repeat(200));
    });

    it('should return parsed image details for capture_screen', () => {
      // 4 chars -> 3 bytes
      const base64 = 'TQ=='; // 'M'
      const input = `data:image/png;base64,${base64}`;
      const preview = toolResultPreview('capture_screen', input);
      expect(preview).toBe('[image image/png, decoded bytes=1]');
    });

    it('should correctly calculate decoded bytes for various padding', () => {
      // 'Ma' -> 'TWE=' (1 pad)
      const base64_1pad = 'TWE=';
      const input1 = `data:image/png;base64,${base64_1pad}`;
      expect(toolResultPreview('capture_screen', input1)).toBe('[image image/png, decoded bytes=2]');

      // 'Man' -> 'TWFu' (0 pad)
      const base64_0pad = 'TWFu';
      const input0 = `data:image/png;base64,${base64_0pad}`;
      expect(toolResultPreview('capture_screen', input0)).toBe('[image image/png, decoded bytes=3]');
    });

    it('should handle raw base64 input correctly', () => {
        // Mock iVBOR start to trigger PNG detection
        // iVBORw0K is 'iVBORw0K' (8 chars) -> 6 bytes
        const base64 = 'iVBORw0K';
        const preview = toolResultPreview('capture_screen', base64);
        expect(preview).toBe('[image image/png, decoded bytes=6]');
    });
  });
});
