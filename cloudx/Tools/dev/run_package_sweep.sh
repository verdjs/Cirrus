#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

packages=(
  CloudXModels
  DiagnosticsKit
  InputBridge
  XCloudAPI
  StreamingCore
  VideoRenderingKit
  CloudXCore
)

for pkg in "${packages[@]}"; do
  echo "swift test --package-path Packages/$pkg"
  swift test --package-path "Packages/$pkg"
done
