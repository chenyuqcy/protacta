#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  printf '%s\n' 'Usage: scripts/test_first_fold.sh SIMULATOR_UDID' >&2
  exit 2
fi

task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$task_root"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
task_run="output/validation/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$task_run"
python3 scripts/generate_xcode_project.py

xcodebuild -project ios/Protacta.xcodeproj -scheme Protacta-StoreKit \
  -destination "platform=iOS Simulator,id=$1" \
  -derivedDataPath output/DerivedData \
  -resultBundlePath "$task_run/FirstFold.xcresult" \
  -parallel-testing-enabled NO \
  -only-testing:ProtactaTests/PaperRegistrationTests \
  -only-testing:ProtactaTests/PaperGuideSessionTests \
  -only-testing:ProtactaTests/PaperGuideControllerTests \
  -only-testing:ProtactaTests/PaperVisionTrackerTests \
  -only-testing:ProtactaTests/LearningControllerTests \
  -only-testing:ProtactaTests/LessonVoiceActionsTests \
  -only-testing:ProtactaTests/VoiceCommandTests \
  -only-testing:ProtactaTests/VoiceRecoveryPolicyTests \
  -only-testing:ProtactaUITests/PaperGuideUITests \
  test > "$task_run/tests.log" 2>&1
printf 'Results: %s\n' "$task_run"
