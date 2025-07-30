#!/usr/bin/env bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
RELEASE_MODE=false
LINT_MODE=false
TEST_MODE=false
CLEAN_MODE=false
VERBOSE=false

for arg in "$@"; do
  case $arg in
    --release)
      RELEASE_MODE=true
      ;;
    --lint)
      LINT_MODE=true
      ;;
    --test)
      TEST_MODE=true
      ;;
    --clean)
      CLEAN_MODE=true
      ;;
    --verbose|-v)
      VERBOSE=true
      ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo "Options:"
      echo "  --release    Build optimized release binary"
      echo "  --lint       Run SwiftLint and SwiftFormat"
      echo "  --test       Run Swift tests"
      echo "  --clean      Clean build artifacts"
      echo "  --verbose    Verbose output"
      echo "  --help       Show this help"
      exit 0
      ;;
  esac
done

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

# Change to native directory
cd "$(dirname "$0")/../native"

# Clean if requested
if [[ "$CLEAN_MODE" == true ]]; then
  log_info "Cleaning build artifacts..."
  rm -rf bin/ .build/
  log_success "Cleaned build artifacts"
  exit 0
fi

# Lint Swift code
if [[ "$LINT_MODE" == true ]]; then
  log_info "Running Swift code quality checks..."
  
  # Step 1: Format code first (SwiftFormat)
  if command -v swiftformat &> /dev/null; then
    log_info "Formatting Swift code..."
    if swiftformat .; then
      log_success "SwiftFormat applied successfully"
    else
      log_error "SwiftFormat failed"
      exit 1
    fi
  else
    log_warning "SwiftFormat not installed. Install with: brew install swiftformat"
  fi
  
  # Step 2: Then run linting (SwiftLint) 
  if command -v swiftlint &> /dev/null; then
    log_info "Running SwiftLint..."
    if swiftlint --quiet; then
      log_success "SwiftLint passed"
    else
      log_error "SwiftLint found issues (after formatting)"
      log_info "This suggests a configuration conflict between SwiftFormat and SwiftLint"
      exit 1
    fi
  else
    log_warning "SwiftLint not installed. Install with: brew install swiftlint"
  fi
fi

# Run tests
if [[ "$TEST_MODE" == true ]]; then
  log_info "Running Swift tests..."
  if swift test; then
    log_success "All tests passed"
  else
    log_error "Tests failed"
    exit 1
  fi
fi

# Create output directory
mkdir -p bin

# Build with appropriate optimization level
if [[ "$RELEASE_MODE" == true ]]; then
  log_info "Building SelectionTap (Release Mode)..."
  
  BUILD_CMD="xcrun swiftc SelectionTap.swift -O -whole-module-optimization -o bin/SelectionTap"
  
  if [[ "$VERBOSE" == true ]]; then
    BUILD_CMD="$BUILD_CMD -v"
  fi
  
  if eval $BUILD_CMD; then
    # Strip debug symbols for smaller binary
    strip bin/SelectionTap
    SIZE=$(du -h bin/SelectionTap | cut -f1)
    log_success "SelectionTap built (Release) -> bin/SelectionTap ($SIZE)"
  else
    log_error "Release build failed"
    exit 1
  fi
else
  log_info "Building SelectionTap (Development Mode)..."
  
  # Build using Swift Package Manager
  BUILD_CMD="swift build -c debug"
  
  if [[ "$RELEASE" == true ]]; then
    BUILD_CMD="swift build -c release"
  fi
  
  if [[ "$VERBOSE" == true ]]; then
    BUILD_CMD="$BUILD_CMD -v"
  fi
  
  if eval $BUILD_CMD; then
    # Copy the built binary to the expected location
    if [[ "$RELEASE" == true ]]; then
      BUILT_BINARY=".build/release/SelectionTap"
    else
      BUILT_BINARY=".build/debug/SelectionTap"
    fi
    
    mkdir -p bin
    cp "$BUILT_BINARY" bin/SelectionTap
    
    SIZE=$(du -h bin/SelectionTap | cut -f1)
    if [[ "$RELEASE" == true ]]; then
      log_success "SelectionTap built (Release) -> bin/SelectionTap ($SIZE)"
    else
      log_success "SelectionTap built (Development) -> bin/SelectionTap ($SIZE)"
    fi
  else
    log_error "Build failed"
    exit 1
  fi
fi

# Verify the binary works
if [[ -x bin/SelectionTap ]]; then
  log_success "Binary is executable"
  
  # Quick functionality test
  if timeout 2s bin/SelectionTap --help 2>/dev/null || true; then
    log_success "Binary responds to basic commands"
  fi
else
  log_error "Binary is not executable"
  exit 1
fi

# Show build summary
log_info "Build Summary:"
echo "  📦 Binary: $(pwd)/bin/SelectionTap"
echo "  📏 Size: $(du -h bin/SelectionTap | cut -f1)"
echo "  🏗️  Mode: $([ "$RELEASE_MODE" == true ] && echo "Release" || echo "Development")"
echo "  🔧 Swift: $(swift --version | head -n1)"
