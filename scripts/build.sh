#!/bin/bash
# Build one or both platforms. Prints only the failure lines when something breaks.
set -o pipefail
cd "$(dirname "$0")/.." || exit 1

PLATFORM="${1:-both}"   # mac | ios | watch | both | all
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
if [ "$PLATFORM" = "mac" ] || [ "$PLATFORM" = "both" ] || [ "$PLATFORM" = "all" ]; then
  run "platform=macOS" "macOS" || status=1
fi
if [ "$PLATFORM" = "ios" ] || [ "$PLATFORM" = "both" ] || [ "$PLATFORM" = "all" ]; then
  run "platform=iOS Simulator,name=$SIM_NAME" "iOS" || status=1
fi
if [ "$PLATFORM" = "watch" ] || [ "$PLATFORM" = "all" ]; then
  # Built against the SDK rather than a destination: this machine has the
  # watchOS SDK but no watchOS simulator runtime, and a destination-based build
  # fails on that alone.
  echo "── watchOS (build) ──"
  # The watchOS SDK ships with Xcode, but building needs the platform *support*
  # package too, which is a separate multi-gigabyte download:
  #   xcodebuild -downloadPlatform watchOS
  # Without it xcodebuild reports "Found no destinations", which reads like a
  # project fault and is not one.
  if ! xcrun simctl list runtimes 2>/dev/null | grep -qi watchos; then
    echo "⚠️  watchOS platform support is not installed on this machine."
    echo "   Install it with: xcodebuild -downloadPlatform watchOS"
    echo "   Falling back to a type-check of the watch sources."
    watch_sdk_path=$(xcrun --sdk watchsimulator --show-sdk-path 2>/dev/null)
    if [ -z "$watch_sdk_path" ]; then
      echo "❌ watchOS build FAILED (no watchOS SDK either)"
      exit 1
    fi
    swiftc -typecheck -swift-version 6 -sdk "$watch_sdk_path" \
      -target arm64-apple-watchos11.0-simulator \
      FlowmapWatch/*.swift \
      Flowmap/Services/WatchSyncPayloads.swift Flowmap/Services/WatchSyncService.swift \
      Flowmap/DesignSystem/FlowTheme.swift Flowmap/DesignSystem/Typography.swift \
      Flowmap/DesignSystem/Spacing.swift Flowmap/Models/DurationFormatter.swift || status=1
    swiftc -typecheck -swift-version 6 -sdk "$watch_sdk_path" \
      -target arm64-apple-watchos11.0-simulator \
      FlowmapWatchWidget/*.swift \
      Flowmap/Services/WatchSyncPayloads.swift \
      Flowmap/DesignSystem/FlowTheme.swift Flowmap/DesignSystem/Typography.swift \
      Flowmap/DesignSystem/Spacing.swift Flowmap/Models/DurationFormatter.swift || status=1
    [ $status -eq 0 ] && echo "✅ watchOS sources type-check clean (not a full build)"
    exit $status
  fi

  # The bare `watchsimulator` alias resolves to nothing without a runtime, so the
  # versioned SDK name is read back from the toolchain.
  watch_sdk=$(xcodebuild -showsdks | grep -o 'watchsimulator[0-9.]*' | tail -1)
  watch_derived=()
  [ -n "$FLOWMAP_DERIVED" ] && watch_derived=(-derivedDataPath "$FLOWMAP_DERIVED")
  out=$(xcodebuild -project Flowmap.xcodeproj -scheme FlowmapWatch \
        -sdk "$watch_sdk" -configuration Debug "${watch_derived[@]}" \
        CODE_SIGNING_ALLOWED=NO build 2>&1)
  if [ $? -eq 0 ]; then
    echo "✅ watchOS build SUCCEEDED"
  else
    echo "$out" | grep -E "error:|\*\* .* FAILED \*\*" | sort -u | head -40
    echo "❌ watchOS build FAILED"
    status=1
  fi
fi
exit $status
