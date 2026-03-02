import { describe, it, expect } from 'vitest';
import { parseImageToolResult, toolResultPreview } from '../src/bridge.js';

describe('image_parsing', () => {
  describe('parseImageToolResult', () => {
    it('should parse standard base64 data URL', () => {
      const result = parseImageToolResult('data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');
      expect(result).toEqual({
        mediaType: 'image/png',
        data: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII='
      });
    });

    it('should handle leading and trailing whitespace', () => {
      const result = parseImageToolResult('   \n\tdata:image/jpeg;base64,/9j/4AAQSkZJRgABAQEAAAAAAAD/2wBDAAoHBwkHBgoJCAkLCwoMDxkQDw4ODx4WFxIZJCAmJSMgIyIoLTkwKCo2MzIlNzQ1Ljc4Ozw9KC0+RjU8QTg5PDT...   \n');
      expect(result).toEqual({
        mediaType: 'image/jpeg',
        data: '/9j/4AAQSkZJRgABAQEAAAAAAAD/2wBDAAoHBwkHBgoJCAkLCwoMDxkQDw4ODx4WFxIZJCAmJSMgIyIoLTkwKCo2MzIlNzQ1Ljc4Ozw9KC0+RjU8QTg5PDT...'
      });
    });

    it('should detect raw base64 PNG', () => {
      const result = parseImageToolResult('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');
      expect(result).toEqual({
        mediaType: 'image/png',
        data: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII='
      });
    });

    it('should detect raw base64 JPEG', () => {
      const result = parseImageToolResult('/9j/4AAQSkZJRgABAQEAAAAAAAD/2wBDAAoHBwkHBgoJCAkLCwoMDxkQDw4ODx4WFxIZJCAmJSMgIyIoLTkwKCo2MzIlNzQ1Ljc4Ozw9KC0+RjU8QTg5PDT...');
      expect(result).toEqual({
        mediaType: 'image/jpeg',
        data: '/9j/4AAQSkZJRgABAQEAAAAAAAD/2wBDAAoHBwkHBgoJCAkLCwoMDxkQDw4ODx4WFxIZJCAmJSMgIyIoLTkwKCo2MzIlNzQ1Ljc4Ozw9KC0+RjU8QTg5PDT...'
      });
    });

    it('should detect raw base64 GIF', () => {
      const result = parseImageToolResult('R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==');
      expect(result).toEqual({
        mediaType: 'image/gif',
        data: 'R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw=='
      });
    });

    it('should detect raw base64 WEBP', () => {
      const result = parseImageToolResult('UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA==');
      expect(result).toEqual({
        mediaType: 'image/webp',
        data: 'UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA=='
      });
    });

    it('should return null for invalid inputs', () => {
      expect(parseImageToolResult('')).toBeNull();
      expect(parseImageToolResult('   ')).toBeNull();
      expect(parseImageToolResult('invalid base64 string')).toBeNull();
    });
  });

  describe('toolResultPreview', () => {
    it('should correctly preview screen capture results with math-based byte calculation', () => {
      // "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=" is 92 characters
      // (92 * 3) / 4 = 69
      // It has 1 padding character '=' at the end, so decoded length is 69 - 1 = 68.
      const rawResult = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';
      const preview = toolResultPreview('capture_screen', rawResult);
      expect(preview).toBe('[image image/png, decoded bytes=68]');
    });

    it('should correctly handle a non-image tool name', () => {
      const preview = toolResultPreview('read_file', 'hello world');
      expect(preview).toBe('hello world');
    });

    it('should properly truncate long results for non-image tools', () => {
      const longString = 'a'.repeat(300);
      const preview = toolResultPreview('read_file', longString);
      expect(preview.length).toBe(200);
      expect(preview).toBe('a'.repeat(200));
    });
  });
});
