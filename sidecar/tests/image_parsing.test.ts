import { describe, it, expect } from 'vitest';
import { parseImageToolResult } from '../src/bridge.js';

describe('parseImageToolResult', () => {
  it('should parse valid PNG base64', () => {
    const raw = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
    const result = parseImageToolResult(raw);
    expect(result).toEqual({ mediaType: 'image/png', data: raw });
  });

  it('should parse valid JPEG base64', () => {
    const raw = '/9j/4AAQSkZJRgABAQEAAAAAAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwH7/9k=';
    const result = parseImageToolResult(raw);
    expect(result).toEqual({ mediaType: 'image/jpeg', data: raw });
  });

  it('should parse data URL with PNG', () => {
    const data = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
    const raw = `data:image/png;base64,${data}`;
    const result = parseImageToolResult(raw);
    expect(result).toEqual({ mediaType: 'image/png', data });
  });

  it('should parse data URL with JPEG', () => {
    const data = '/9j/4AAQSkZJRgABAQEAAAAAAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwH7/9k=';
    const raw = `data:image/jpeg;base64,${data}`;
    const result = parseImageToolResult(raw);
    expect(result).toEqual({ mediaType: 'image/jpeg', data });
  });

  it('should handle leading/trailing whitespace', () => {
    const raw = '   iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==   \n';
    const result = parseImageToolResult(raw);
    expect(result).toEqual({ mediaType: 'image/png', data: raw.trim() });
  });

  it('should return null for invalid input', () => {
    expect(parseImageToolResult('not an image')).toBeNull();
    expect(parseImageToolResult('')).toBeNull();
    expect(parseImageToolResult('   ')).toBeNull();
  });

  // Benchmark
  it('should be fast on large inputs', () => {
      const largeBase64 = 'iVBOR' + 'A'.repeat(1024 * 1024 * 5); // 5MB
      const start = performance.now();
      const result = parseImageToolResult(largeBase64);
      const end = performance.now();
      expect(result).not.toBeNull();
      expect(result?.mediaType).toBe('image/png');
      console.log(`Duration for 5MB: ${end - start}ms`);
  });

  it('should be fast on large data URL (25MB)', () => {
      const data = 'A'.repeat(1024 * 1024 * 25); // 25MB
      const raw = `data:image/png;base64,${data}`;
      const start = performance.now();
      const result = parseImageToolResult(raw);
      const end = performance.now();
      expect(result).not.toBeNull();
      expect(result?.mediaType).toBe('image/png');
      console.log(`Duration for 25MB Data URL: ${end - start}ms`);
  });
});
