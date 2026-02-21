import { describe, it, expect } from 'vitest';
import { parseImageToolResult, toolResultPreview } from '../src/bridge';

describe('Image Parsing Logic', () => {
  const base64Chunk = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
  const largeBase64 = base64Chunk.repeat(10);
  const dataUrl = `data:image/png;base64,${largeBase64}`;

  it('correctly parses data URLs', () => {
    const result = parseImageToolResult(dataUrl);
    expect(result).not.toBeNull();
    expect(result?.mediaType).toBe('image/png');
    expect(result?.data).toBe(largeBase64);
  });

  it('correctly parses raw base64 (PNG)', () => {
    const raw = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
    const result = parseImageToolResult(raw);
    expect(result).not.toBeNull();
    expect(result?.mediaType).toBe('image/png');
    expect(result?.data).toBe(raw);
  });

  it('correctly handles whitespace', () => {
    const raw = '   iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=   ';
    const result = parseImageToolResult(raw);
    expect(result).not.toBeNull();
    expect(result?.mediaType).toBe('image/png');
    expect(result?.data).toBe(raw.trim());
  });

  it('returns null for invalid data URL', () => {
    expect(parseImageToolResult('data:image/png;base64')).toBeNull(); // Missing comma
    expect(parseImageToolResult('data:image/pngbase64,foo')).toBeNull(); // Missing ;
    expect(parseImageToolResult('data:text/plain;base64,foo')).toBeNull(); // Not image
  });

  it('previews tool result correctly', () => {
     const preview = toolResultPreview('capture_screen', dataUrl);
     expect(preview).toContain('image/png');

     // base64Chunk length is 92. It ends with '='.
     // largeBase64 is 920 chars. It ends with '='.
     // Expected decoded bytes: Math.floor(920 * 3 / 4) - 1 = 690 - 1 = 689.
     expect(preview).toContain('decoded bytes=689');
  });
});
