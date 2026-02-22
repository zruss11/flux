import { describe, it, expect } from 'vitest';
import { parseImageToolResult, toolResultPreview } from '../src/bridge.js';

describe('Image Parsing & Preview', () => {
  describe('parseImageToolResult', () => {
    it('should parse data URL correctly', () => {
      const input = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGNiAAAABgADNjd8qAAAAABJRU5ErkJggg==';
      const result = parseImageToolResult(input);
      expect(result).not.toBeNull();
      expect(result?.mediaType).toBe('image/png');
      expect(result?.data).toBe('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGNiAAAABgADNjd8qAAAAABJRU5ErkJggg==');
    });

    it('should parse raw PNG base64', () => {
      const input = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGNiAAAABgADNjd8qAAAAABJRU5ErkJggg==';
      const result = parseImageToolResult(input);
      expect(result).not.toBeNull();
      expect(result?.mediaType).toBe('image/png');
      expect(result?.data).toBe(input);
    });

    it('should parse raw JPEG base64 (start with /9j/)', () => {
      const input = '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9sAQwAGBgYGBgYICAgICgwKCwwNDAwMDQwODg4ODg4RERERERERERERERERERERERERERERERERERERERERERERERER/9oADAMBAAIRAxEAPwD38AAADgCiiigD/9k=';
      const result = parseImageToolResult(input);
      expect(result).not.toBeNull();
      expect(result?.mediaType).toBe('image/jpeg');
      expect(result?.data).toBe(input);
    });

    it('should return null for invalid input', () => {
      const input = 'not an image';
      const result = parseImageToolResult(input);
      expect(result).toBeNull();
    });

    it('should handle whitespace in input', () => {
      const input = '   data:image/webp;base64,UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAAAAQ==   ';
      const result = parseImageToolResult(input);
      expect(result).not.toBeNull();
      expect(result?.mediaType).toBe('image/webp');
      expect(result?.data).toBe('UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAAAAQ==');
    });
  });

  describe('toolResultPreview', () => {
    it('should return truncated text for non-image tools', () => {
      const longText = 'a'.repeat(300);
      const result = toolResultPreview('read_file', longText);
      expect(result.length).toBeLessThan(longText.length);
      expect(result).toBe(longText.substring(0, 200));
    });

    it('should return formatted preview for capture_screen with valid image', () => {
      // Base64 'ABCD' -> 3 bytes
      // 'A' -> 6 bits, 'B' -> 6 bits, ... 4 chars * 6 bits = 24 bits = 3 bytes.
      // 0 padding.
      const base64 = 'ABCD';
      // ABCD -> 000000 010000 100000 110000 -> 00000001 00001000 00110000 -> 0x01 0x08 0x30
      const input = `data:image/png;base64,${base64}`;
      const result = toolResultPreview('capture_screen', input);
      expect(result).toContain('[image image/png, decoded bytes=3]');
    });

    it('should calculate correct byte length with padding =', () => {
      // 'ABC=' -> 3 chars data -> 18 bits. Padded to 24 bits (4 chars).
      // 'ABC=' -> 6+6+6 = 18 bits. = means last 6 bits are padding?
      // No, '=' means last 6 bits are ignored/padding.
      // Base64 length formula: 3 bytes per 4 chars.
      // 'ABC=' -> 4 chars. (4 * 3) / 4 = 3.
      // Padding = 1. Result = 2 bytes.
      const base64 = 'ABC=';
      const input = `data:image/png;base64,${base64}`;
      const result = toolResultPreview('capture_screen', input);
      expect(result).toContain('decoded bytes=2');
    });

    it('should calculate correct byte length with padding ==', () => {
      // 'AB==' -> 2 chars data + 2 padding.
      // 4 chars -> 3 bytes.
      // Padding = 2. Result = 1 byte.
      const base64 = 'AB==';
      const input = `data:image/png;base64,${base64}`;
      const result = toolResultPreview('capture_screen', input);
      expect(result).toContain('decoded bytes=1');
    });

    it('should handle raw base64 input', () => {
        // iVBOR... is png
        const base64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGNiAAAABgADNjd8qAAAAABJRU5ErkJggg==';
        // Length 100 chars?
        // Let's just trust our calculation.
        // Length 92. 92 * 3 / 4 = 69.
        // Padding == -> -2 -> 67 bytes.
        const result = toolResultPreview('capture_screen', base64);
        expect(result).toContain('image/png');
        expect(result).toContain('decoded bytes=67');
    });

    it('should fallback to truncation if image parsing fails', () => {
      const input = 'invalid image data';
      const result = toolResultPreview('capture_screen', input);
      expect(result).toBe('invalid image data');
    });
  });
});
