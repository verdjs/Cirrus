#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

xcodebuild -quiet \
  -workspace CloudX.xcworkspace \
  -scheme CloudX-Validation \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=latest' \
  -derivedDataPath /tmp/cloudx_shell_state_tests \
  -clonedSourcePackagesDirPath /tmp/cloudx_shell_state_tests_spm \
  -only-testing:CloudXTests/CloudLibraryStateSnapshotTests \
  -only-testing:CloudXTests/CloudLibraryLoadStateTests \
  -only-testing:CloudXTests/CloudLibraryRouteStateTests \
  -only-testing:CloudXTests/CloudLibraryFocusStateTests \
  -only-testing:CloudXTests/CloudLibraryBackActionPolicyTests \
  -only-testing:CloudXTests/CloudLibraryShellHostActionTests \
  -only-testing:CloudXTests/CloudLibraryRoutePresentationBuilderTests \
  -only-testing:CloudXTests/CloudLibraryShellHostTests \
  test
