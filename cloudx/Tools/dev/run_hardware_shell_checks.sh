#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

HARDWARE_DEVICE_ID="${HARDWARE_DEVICE_ID:-${TVOS_HARDWARE_DEVICE_ID:-}}"
if [[ -z "$HARDWARE_DEVICE_ID" ]]; then
  echo "Error: set HARDWARE_DEVICE_ID or TVOS_HARDWARE_DEVICE_ID before running hardware shell checks." >&2
  exit 1
fi
WORKSPACE_PATH="$REPO_ROOT/CloudX.xcworkspace"

xcodebuild \
  -workspace "$WORKSPACE_PATH" \
  -scheme CloudX-ShellUI \
  -destination "id=$HARDWARE_DEVICE_ID" \
  -derivedDataPath /tmp/cloudx_hardware_shell_ready \
  -clonedSourcePackagesDirPath /tmp/cloudx_hardware_shell_ready_spm \
  -only-testing:CloudXUITests/ShellCheckpointUITests/testStoredAuthenticatedShellPublishesShellReadyBeforeRouteLandmarks \
  test

xcodebuild \
  -workspace "$WORKSPACE_PATH" \
  -scheme CloudX-ShellUI \
  -destination "id=$HARDWARE_DEVICE_ID" \
  -derivedDataPath /tmp/cloudx_hardware_shell_roundtrip \
  -clonedSourcePackagesDirPath /tmp/cloudx_hardware_shell_roundtrip_spm \
  -only-testing:CloudXUITests/ShellCheckpointUITests/testHomePlayNowLaunchAndBackReturnsToHome \
  test

xcodebuild \
  -workspace "$WORKSPACE_PATH" \
  -scheme CloudX-ShellUI \
  -destination "id=$HARDWARE_DEVICE_ID" \
  -derivedDataPath /tmp/cloudx_hardware_shell_exit_completion \
  -clonedSourcePackagesDirPath /tmp/cloudx_hardware_shell_exit_completion_spm \
  -only-testing:CloudXUITests/ShellCheckpointUITests/testStreamExitCompletionMarkerFollowsHomeVisibilityAndFocusRestore \
  test
