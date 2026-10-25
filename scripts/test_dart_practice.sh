#!/bin/sh
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  printf '%s\n' 'Usage: scripts/test_dart_practice.sh SIMULATOR_UDID [logic|phone|tablet]' >&2
  exit 2
fi

task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$task_root"
task_device=$1
task_mode=${2:-logic}
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
task_run="output/validation/$(date -u +%Y%m%dT%H%M%SZ)-dart-$task_mode"
mkdir -p "$task_run"
python3 scripts/generate_xcode_project.py

set -- -project ios/Protacta.xcodeproj -scheme Protacta-StoreKit \
  -destination "platform=iOS Simulator,id=$task_device" \
  -derivedDataPath output/DerivedData -resultBundlePath "$task_run/Practice.xcresult" \
  -parallel-testing-enabled NO

case "$task_mode" in
  logic)
    for task_suite in DartPracticeCourseTests DartPracticeSessionTests DartPracticeControllerTests DartOutlineCheckTests PrintedPaperTrackerTests PracticeValidationCaptureTests PracticeValidationControllerTests PaperRegistrationTests PaperGuideSessionTests PaperGuideControllerTests PaperVisionTrackerTests PaperGeometryTests LearningControllerTests LessonVoiceActionsTests VoiceCommandTests VoiceRecoveryPolicyTests VoiceGuideStateTests; do
      set -- "$@" "-only-testing:ProtactaTests/$task_suite"
    done
    ;;
  phone)
    set -- "$@" -only-testing:ProtactaUITests/DartPracticeUITests -only-testing:ProtactaUITests/PaperGuideUITests -only-testing:ProtactaUITests/PracticeValidationUITests \
      -skip-testing:ProtactaUITests/DartPracticeUITests/testTabletLandscapeCanReachSetupCheckAndConfirmation \
      -skip-testing:ProtactaUITests/PaperGuideUITests/testGuideControlsRemainReachableOnTabletInLandscape
    ;;
  tablet)
    set -- "$@" -only-testing:ProtactaUITests/DartPracticeUITests -only-testing:ProtactaUITests/PaperGuideUITests -only-testing:ProtactaUITests/PracticeValidationUITests
    ;;
  *) printf '%s\n' 'Mode must be logic, phone or tablet.' >&2; exit 2 ;;
esac

xcodebuild "$@" test > "$task_run/tests.log" 2>&1
printf 'Results: %s\n' "$task_run"
