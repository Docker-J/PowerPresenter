#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

mkdir -p .build/tmp .build/cache

echo "🚀 Launching PowerPresenter..."
TMPDIR="${DIR}/.build/tmp" \
SWIFT_MODULE_CACHE_PATH="${DIR}/.build/cache" \
CLANG_MODULE_CACHE_PATH="${DIR}/.build/cache" \
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" \
swift run --disable-sandbox PowerPresenter
