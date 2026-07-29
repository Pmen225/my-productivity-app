#!/bin/bash
# Export the screenshots a UI-test run attached, INCLUDING a run that failed.
#
# screenshots.sh runs under `set -e`, so a failing test aborts it before its own
# export step and you get zero images — even though every shot taken before the
# failure is sitting in the result bundle. This recovers them without re-running.
#
#   ./scripts/export-shots.sh [result-bundle] [output-dir]
#
# Defaults to the bundle screenshots.sh writes, and to Screenshots/.
set -euo pipefail
cd "$(dirname "$0")/.."
RESULT="${1:-${TMPDIR:-/tmp}/flowmap-shots.xcresult}"
OUT="${2:-Screenshots}"

[ -d "$RESULT" ] || { echo "No result bundle at $RESULT" >&2; exit 1; }
mkdir -p "$OUT"
EXPORT_DIR="$(mktemp -d)"
xcrun xcresulttool export attachments --path "$RESULT" --output-path "$EXPORT_DIR"
python3 - "$EXPORT_DIR" "$OUT" <<'PY'
import json, os, re, shutil, sys
src, dst = sys.argv[1], sys.argv[2]
count = 0
for test in json.load(open(os.path.join(src, "manifest.json"))):
    for att in test.get("attachments", []):
        name = re.sub(r"_\d+_[0-9A-F-]{36}", "", att.get("suggestedHumanReadableName") or att["exportedFileName"])
        if not name.endswith(".png"):
            continue
        shutil.copy(os.path.join(src, att["exportedFileName"]), os.path.join(dst, name))
        print("exported", name)
        count += 1
print(f"{count} screenshots -> {dst}")
PY
