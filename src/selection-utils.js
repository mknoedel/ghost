// Centralized selection validation and utilities

/**
 * Validates if a text selection is worth showing in the popup
 * @param {string} text - The selected text
 * @returns {boolean} - Whether the selection is valid
 */
function isValidSelection(text) {
  if (!text || typeof text !== 'string') {
    return false;
  }

  const trimmed = text.trim();

  // Must have actual content
  if (trimmed.length === 0) {
    return false;
  }

  return true;
}

/**
 * Truncates text for display in the popup
 * @param {string} text - The text to truncate
 * @param {number} maxLength - Maximum length (default: 50)
 * @returns {string} - Truncated text with ellipsis if needed
 */
function truncateForDisplay(text, maxLength = 50) {
  if (!text || typeof text !== 'string') {
    return '';
  }

  const trimmed = text.trim();
  if (trimmed.length <= maxLength) {
    return trimmed;
  }

  return trimmed.substring(0, maxLength - 3) + '...';
}

/**
 * Sanitizes text for safe display in HTML
 * @param {string} text - The text to sanitize
 * @returns {string} - HTML-safe text
 */
function sanitizeForHTML(text) {
  if (!text || typeof text !== 'string') {
    return '';
  }

  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * Detects the type of selected content
 * @param {string} text - The selected text
 * @returns {string} - Content type: 'url', 'email', 'number', 'text'
 */
function detectContentType(text) {
  if (!text || typeof text !== 'string') {
    return 'text';
  }

  const trimmed = text.trim();

  // URL detection
  if (/^https?:\/\/\S+$/.test(trimmed)) {
    return 'url';
  }

  // Email detection
  if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmed)) {
    return 'email';
  }

  // Number detection (including phone numbers)
  if (/^\+?[\d\s\-().]$/.test(trimmed) && trimmed.replace(/\D/g, '').length >= 3) {
    return 'number';
  }

  return 'text';
}

module.exports = {
  isValidSelection,
  truncateForDisplay,
  sanitizeForHTML,
  detectContentType
};
