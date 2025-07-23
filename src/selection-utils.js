// Centralized selection validation and utilities

function isValidSelection(text) {
  return text && 
         text.trim().length > 0 && 
         text.toLowerCase().includes('a');
}

module.exports = {
  isValidSelection
};