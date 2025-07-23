#!/usr/bin/env bash
set -e
mkdir -p native/bin
xcrun swiftc native/SelectionTap.swift -O -o native/bin/SelectionTap
echo "✅ SelectionTap built -> native/bin/SelectionTap"
