#!/bin/bash
# Build one or both platforms. Prints only the failure lines when something breaks.
set -o pipefail
cd "$(dirname "$0")/.." || exit 1

PLATFORM="${1:-both}"
ACTION="${2:-build}"
SIM_NAME="${FLOWMAP_SIM:-iPhone 17 Pro}"

run() {
  local dest="$1" label="$2"
  echo "── $label ($ACTION) ──"
  local out
  # Parallel agents each need their own build directory, or they fight over one
  # DerivedData tree and fail for reasons unrelated to their code.
  local derived=()
  [ -n "$FLOWMAP_DERIVED" ] && derived=(-derivedDataPath "$FLOWMAP_DERIVED")

  out=$(xcodebuild -project Flowmap.xcodeproj -scheme Flowmap \
        -destination "$dest" -configuration Debug "${derived[@]}" \
        CODE_SIGNING_ALLOWED=NO "$ACTION" 2>&1)
  local code=$?
  if [ $code -eq 0 ]; then
    echo "$out" | grep -E "Test Suite .* (passed|failed)|Executed .* tests" | tail -5
    echo "✅ $label $ACTION SUCCEEDED"
  else
    echo "$out" | grep -E "error:|failed:|XCTAssert|Testing failure|\*\* .* FAILED \*\*" | sort -u | head -40
    echo "❌ $label $ACTION FAILED"
  fi
  return $code
}

status=0
if [ "$PLATFORM" = "mac" ] || [ "$PLATFORM" = "both" ]; then
  run "platform=macOS" "macOS" || status=1
fi
if [ "$PLATFORM" = "ios" ] || [ "$PLATFORM" = "both" ]; then
  run "platform=iOS Simulator,name=$SIM_NAME" "iOS" || status=1
fi
exit $status
