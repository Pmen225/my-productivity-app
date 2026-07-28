#!/bin/bash
# Regenerate Screenshots/ from the UI screenshot suite.
set -euo pipefail
cd "$(dirname "$0")/.."
RESULT="${TMPDIR:-/tmp}/flowmap-shots.xcresult"
rm -rf "$RESULT"
xcodebuild -project Flowmap.xcodeproj -scheme Flowmap \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:FlowmapUITests/ScreenshotTests \
  -resultBundlePath "$RESULT" CODE_SIGNING_ALLOWED=NO test
mkdir -p Screenshots
EXPORT_DIR="$(mktemp -d)"
xcrun xcresulttool export attachments --path "$RESULT" --output-path "$EXPORT_DIR"
python3 - "$EXPORT_DIR" Screenshots <<'PY'
import json, os, re, shutil, sys
src, dst = sys.argv[1], sys.argv[2]
manifest = os.path.join(src, "manifest.json")
if os.path.exists(manifest):
    for test in json.load(open(manifest)):
        for att in test.get("attachments", []):
            name = re.sub(r"_\d+_[0-9A-F-]{36}", "", att.get("suggestedHumanReadableName") or att["exportedFileName"])
            if not name.endswith(".png"):
                name += ".png"
            shutil.copy(os.path.join(src, att["exportedFileName"]), os.path.join(dst, name))
            print("exported", name)
else:
    for f in os.listdir(src):
        if f.endswith(".png"):
            shutil.copy(os.path.join(src, f), os.path.join(dst, f))
            print("exported", f)
PY
