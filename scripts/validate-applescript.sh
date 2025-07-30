#!/usr/bin/env bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
  echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
  echo -e "${RED}❌ $1${NC}"
}

# Find all AppleScript files
APPLESCRIPT_DIR="$(dirname "$0")/../src/mac-scripts"
APPLESCRIPT_FILES=$(find "$APPLESCRIPT_DIR" -name "*.applescript" -type f)

if [[ -z "$APPLESCRIPT_FILES" ]]; then
  log_warning "No AppleScript files found in $APPLESCRIPT_DIR"
  exit 0
fi

log_info "Validating AppleScript files..."

# Track validation results
TOTAL_FILES=0
VALID_FILES=0
SYNTAX_ERRORS=0
STYLE_WARNINGS=0

# Validate each AppleScript file
for file in $APPLESCRIPT_FILES; do
  TOTAL_FILES=$((TOTAL_FILES + 1))
  filename=$(basename "$file")
  
  echo ""
  log_info "Validating $filename..."
  
  # Check syntax by compiling the script
  if osacompile -o /tmp/test_script.scpt "$file" 2>/dev/null; then
    log_success "✓ Syntax valid"
    VALID_FILES=$((VALID_FILES + 1))
  else
    log_error "✗ Syntax error detected"
    SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
    
    # Show detailed error
    log_error "Compilation failed for $filename:"
    osacompile -o /tmp/test_script.scpt "$file" 2>&1 || true
    continue
  fi
  
  # Style and best practice checks
  WARNINGS=0
  
  # Check for proper error handling
  if ! grep -q "on error" "$file"; then
    log_warning "⚠️  No error handling found - consider adding try/on error blocks"
    WARNINGS=$((WARNINGS + 1))
  fi
  
  # Check for hardcoded delays (should be minimized)
  DELAY_COUNT=$(grep -c "delay [0-9]*\.*[0-9]*" "$file" 2>/dev/null)
  if [[ "$DELAY_COUNT" -gt 3 ]]; then
    log_warning "⚠️  Many delay statements found ($DELAY_COUNT) - consider optimizing"
    WARNINGS=$((WARNINGS + 1))
  fi
  
  # Check for proper logging
  if grep -q "log " "$file" && ! grep -q "logInfo\|logError\|logDebug" "$file"; then
    log_warning "⚠️  Using basic 'log' instead of structured logging functions"
    WARNINGS=$((WARNINGS + 1))
  fi
  
  # Check for shell script injection vulnerabilities
  # Simple check: look for shell scripts with string concatenation (&) that don't use quoted form of
  SHELL_WITH_CONCAT=$(grep -c "do shell script.*&" "$file" 2>/dev/null)
  SAFE_QUOTED_FORMS=$(grep -c "quoted form of" "$file" 2>/dev/null)
  
  # Only warn if there's string concatenation in shell scripts but no proper escaping
  if [[ "$SHELL_WITH_CONCAT" -gt 0 && "$SAFE_QUOTED_FORMS" -eq 0 ]]; then
    log_warning "⚠️  Potential shell injection risk detected - use 'quoted form of' for variables"
    WARNINGS=$((WARNINGS + 1))
  elif [[ "$SHELL_WITH_CONCAT" -gt "$SAFE_QUOTED_FORMS" ]]; then
    # More concatenations than quoted forms - might have some unescaped variables
    log_warning "⚠️  Some shell commands may need 'quoted form of' - verify variable escaping"
    WARNINGS=$((WARNINGS + 1))
  fi
  
  # Check for accessibility best practices
  if grep -q "UI elements enabled" "$file" && ! grep -q "checkUIElementsEnabled" "$file"; then
    log_warning "⚠️  Direct UI elements check - consider using utility function"
    WARNINGS=$((WARNINGS + 1))
  fi
  
  STYLE_WARNINGS=$((STYLE_WARNINGS + WARNINGS))
  
  if [[ $WARNINGS -eq 0 ]]; then
    log_success "✓ Style checks passed"
  else
    log_warning "⚠️  $WARNINGS style warnings"
  fi
done

# Clean up temporary files
rm -f /tmp/test_script.scpt

# Summary
echo ""
echo "=================================================================================="
log_info "AppleScript Validation Summary"
echo "  📁 Total files: $TOTAL_FILES"
echo "  ✅ Valid syntax: $VALID_FILES"
echo "  ❌ Syntax errors: $SYNTAX_ERRORS"
echo "  ⚠️  Style warnings: $STYLE_WARNINGS"

if [[ $SYNTAX_ERRORS -eq 0 ]]; then
  log_success "All AppleScript files have valid syntax!"
  
  if [[ $STYLE_WARNINGS -eq 0 ]]; then
    log_success "No style warnings found!"
    exit 0
  else
    log_warning "Style warnings found - consider addressing them for better maintainability"
    exit 0
  fi
else
  log_error "AppleScript validation failed with $SYNTAX_ERRORS syntax errors"
  exit 1
fi