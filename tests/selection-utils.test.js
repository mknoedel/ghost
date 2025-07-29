const { isValidSelection } = require('../src/selection-utils');

describe('Selection Utils', () => {
  describe('isValidSelection', () => {
    test('should accept valid text selections', () => {
      expect(isValidSelection('Hello world')).toBe(true);
      expect(isValidSelection('A longer piece of text that should be valid')).toBe(true);
      expect(isValidSelection('Text with numbers 123')).toBe(true);
    });

    test('should reject empty or whitespace-only selections', () => {
      expect(isValidSelection('')).toBe(false);
      expect(isValidSelection('   ')).toBe(false);
      expect(isValidSelection('\n\t  \n')).toBe(false);
    });

    test('should reject undefined or null selections', () => {
      expect(isValidSelection(undefined)).toBe(false);
      expect(isValidSelection(null)).toBe(false);
    });

    test('should handle edge cases', () => {
      expect(isValidSelection('A')).toBe(true); // Single character
      expect(isValidSelection('   A   ')).toBe(true); // Trimmed content
    });
  });
});