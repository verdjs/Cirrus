#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

xcodebuild -quiet \
  -workspace CloudX.xcworkspace \
  -scheme CloudX-Debug \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=latest' \
  -derivedDataPath /tmp/cloudx_app_smoke \
  -clonedSourcePackagesDirPath /tmp/cloudx_app_smoke_spm \
  -only-testing:CloudXTests/AppBundleSmokeTests \
  test
