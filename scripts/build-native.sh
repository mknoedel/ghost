#!/usr/bin/env bash
set -e

# Parse arguments
RELEASE_MODE=false
if [[ "$1" == "--release" ]]; then
  RELEASE_MODE=true
fi

# Create output directory
mkdir -p native/bin

# Build with appropriate optimization level
if [[ "$RELEASE_MODE" == true ]]; then
  echo "🚀 Building SelectionTap (Release Mode)..."
  xcrun swiftc native/SelectionTap.swift -O -whole-module-optimization -o native/bin/SelectionTap
  # Strip debug symbols for smaller binary
  strip native/bin/SelectionTap
  echo "✅ SelectionTap built (Release) -> native/bin/SelectionTap ($(du -h native/bin/SelectionTap | cut -f1))"
else
  echo "🔨 Building SelectionTap (Development Mode)..."
  xcrun swiftc native/SelectionTap.swift -O -o native/bin/SelectionTap
  echo "✅ SelectionTap built (Development) -> native/bin/SelectionTap ($(du -h native/bin/SelectionTap | cut -f1))"
fi

# Verify the binary works
if [[ -x native/bin/SelectionTap ]]; then
  echo "✅ Binary is executable"
else
  echo "❌ Binary is not executable"
  exit 1
fi
