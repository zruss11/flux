import { describe, it, expect } from 'vitest';
import { parseImageToolResult, toolResultPreview } from '../src/bridge.js';

describe('image parsing', () => {
  it('parses data url', () => {
    expect(parseImageToolResult('  data:image/png;base64,hello  ')).toEqual({ mediaType: 'image/png', data: 'hello' });
  });
  it('parses raw base64', () => {
    expect(parseImageToolResult('  iVBORw0KGgoAAAANSUhEUg  ')).toEqual({ mediaType: 'image/png', data: 'iVBORw0KGgoAAAANSUhEUg' });
    expect(parseImageToolResult('  /9j/4AAQSkZJRgABAQEAS  ')).toEqual({ mediaType: 'image/jpeg', data: '/9j/4AAQSkZJRgABAQEAS' });
  });
  it('previews', () => {
    // "hello" is 5 chars, wait base64 is padded, e.g. "aGVsbG8=" (8 chars)
    expect(toolResultPreview('capture_screen', 'data:image/png;base64,aGVsbG8=')).toBe('[image image/png, decoded bytes=5]');
    expect(Buffer.from('aGVsbG8=', 'base64').length).toBe(5);
  });
});
