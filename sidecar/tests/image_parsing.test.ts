import { describe, it, expect } from 'vitest';
import { toolResultPreview, parseImageToolResult } from '../src/bridge.js';

describe('image parsing', () => {
  describe('parseImageToolResult', () => {
    it('should parse data URL correctly', () => {
      const input = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
      const result = parseImageToolResult(input);
      expect(result).not.toBeNull();
      expect(result?.mediaType).toBe('image/png');
      expect(result?.data).toBe('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
    });

    it('should parse raw base64 correctly (PNG signature)', () => {
      const input = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
      const result = parseImageToolResult(input);
      expect(result).not.toBeNull();
      expect(result?.mediaType).toBe('image/png');
      expect(result?.data).toBe(input);
    });

    it('should parse raw base64 correctly (JPEG signature)', () => {
      const input = '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpcHFyc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD3+iiigD//2Q==';
      const result = parseImageToolResult(input);
      expect(result).not.toBeNull();
      expect(result?.mediaType).toBe('image/jpeg');
      expect(result?.data).toBe(input);
    });

    it('should return null for non-image strings', () => {
      expect(parseImageToolResult('some text')).toBeNull();
      expect(parseImageToolResult('{"json":"object"}')).toBeNull();
    });
  });

  describe('toolResultPreview', () => {
    it('should calculate byte length correctly for base64', () => {
        const toolName = 'capture_screen';

        // 'iVBOR' prefix is PNG.
        const pngBase64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
        const expectedBytes = Buffer.from(pngBase64, 'base64').length;

        const preview = toolResultPreview(toolName, pngBase64);
        expect(preview).toBe(`[image image/png, decoded bytes=${expectedBytes}]`);
    });

    it('should ignore other tools', () => {
        const result = toolResultPreview('read_file', 'some content');
        expect(result).toBe('some content');
    });

    it('should truncate long results for other tools', () => {
        const longText = 'a'.repeat(300);
        const result = toolResultPreview('read_file', longText);
        expect(result.length).toBe(200);
    });
  });
});
