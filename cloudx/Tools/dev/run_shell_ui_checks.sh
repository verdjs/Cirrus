#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

DESTINATION='platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=latest'

run_shell_ui_case() {
  local derived_data_root="$1"
  local cloned_spm_root="$2"
  local test_identifier="$3"

  xcodebuild -quiet \
    -workspace CloudX.xcworkspace \
    -scheme CloudX-ShellUI \
    -destination "$DESTINATION" \
    -derivedDataPath "$derived_data_root" \
    -clonedSourcePackagesDirPath "$cloned_spm_root" \
    -only-testing:"$test_identifier" \
    test
}

# These UI tests are stable in isolation but can become flaky when the simulator
# relaunches between unrelated shell routes inside a single xcodebuild session.
# Keep the proof surface deterministic by isolating each checkpoint.
run_shell_ui_case \
  /tmp/cloudx_shell_checkpoints_nav \
  /tmp/cloudx_shell_checkpoints_nav_spm \
  CloudXUITests/ShellCheckpointUITests/testShellNavigationCheckpoints

run_shell_ui_case \
  /tmp/cloudx_shell_checkpoints_scene_bleed \
  /tmp/cloudx_shell_checkpoints_scene_bleed_spm \
  CloudXUITests/ShellCheckpointUITests/testNoSceneBleedAcrossDestinationSwitches
