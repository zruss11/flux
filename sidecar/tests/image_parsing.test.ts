import { describe, it, expect } from 'vitest';
import { toolResultPreview, parseImageToolResult } from '../src/bridge.js';

describe('Image Parsing & Optimization', () => {
  const base64Pixel = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

  describe('parseImageToolResult', () => {
    it('should parse data URI', () => {
      const input = `data:image/png;base64,${base64Pixel}`;
      const result = parseImageToolResult(input);
      expect(result).toEqual({ mediaType: 'image/png', data: base64Pixel });
    });

    it('should parse raw base64 (PNG)', () => {
      const input = base64Pixel;
      const result = parseImageToolResult(input);
      expect(result).toEqual({ mediaType: 'image/png', data: base64Pixel });
    });

    it('should return null for non-image string', () => {
      expect(parseImageToolResult('not an image')).toBeNull();
    });
  });

  describe('toolResultPreview', () => {
    it('should calculate correct byte length for base64 image', () => {
      // Create a predictable base64 string
      // "Hello" -> "SGVsbG8=" (5 bytes -> 8 chars)
      // "Hello World" -> "SGVsbG8gV29ybGQ=" (11 bytes -> 16 chars)
      const data = 'SGVsbG8gV29ybGQ=';
      const input = `data:image/png;base64,${data}`;

      const preview = toolResultPreview('capture_screen', input);

      // Expected byte length is 11
      expect(preview).toContain('decoded bytes=11');
    });

    it('should handle padding correctly', () => {
      // 1 byte: "a" -> "YQ==" (1 byte, 2 padding)
      const data1 = "YQ==";
      const input1 = `data:image/png;base64,${data1}`;
      expect(toolResultPreview('capture_screen', input1)).toContain('decoded bytes=1');

      // 2 bytes: "ab" -> "YWI=" (2 bytes, 1 padding)
      const data2 = "YWI=";
      const input2 = `data:image/png;base64,${data2}`;
      expect(toolResultPreview('capture_screen', input2)).toContain('decoded bytes=2');

      // 3 bytes: "abc" -> "YWJj" (3 bytes, 0 padding)
      const data3 = "YWJj";
      const input3 = `data:image/png;base64,${data3}`;
      expect(toolResultPreview('capture_screen', input3)).toContain('decoded bytes=3');
    });

    it('should default to short text preview for other tools', () => {
      const result = toolResultPreview('other_tool', 'some long output that should be truncated'.repeat(10));
      expect(result.length).toBeLessThanOrEqual(200);
      expect(result).not.toContain('decoded bytes=');
    });
  });
});
