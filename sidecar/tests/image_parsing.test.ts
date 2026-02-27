import { describe, it, expect } from 'vitest';
import { parseImageToolResult, toolResultPreview } from '../src/bridge';

describe('image_parsing', () => {
  it('parses data URIs correctly', () => {
    const res = parseImageToolResult('  data:image/png;base64,iVBORw0KGgo  ');
    expect(res).toEqual({ mediaType: 'image/png', data: 'iVBORw0KGgo' });
  });

  it('parses raw png correctly', () => {
    const res = parseImageToolResult('  iVBORw0KGgo  ');
    expect(res).toEqual({ mediaType: 'image/png', data: 'iVBORw0KGgo' });
  });

  it('parses raw jpeg correctly', () => {
    const res = parseImageToolResult('  /9j/4AAQSkZJRg  ');
    expect(res).toEqual({ mediaType: 'image/jpeg', data: '/9j/4AAQSkZJRg' });
  });

  it('calculates bytes correctly in preview', () => {
    const rawData = 'iVBORw0KGgo=';
    const preview = toolResultPreview('capture_screen', rawData);

    // len is 12. (12*3)/4 = 9. 1 padding char => 8.
    expect(preview).toBe('[image image/png, decoded bytes=8]');

    // Double check with actual Buffer
    const decodedBytes = Buffer.from(rawData, 'base64').length;
    expect(decodedBytes).toBe(8);
  });
});
