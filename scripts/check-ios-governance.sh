#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

proof_file="state/governance/current-ios-task.md"
proof_tmp=""

cleanup() {
    if [ -n "$proof_tmp" ] && [ -f "$proof_tmp" ]; then
        rm -f "$proof_tmp"
    fi
}

trap cleanup EXIT INT TERM

staged_files=$(git diff --cached --name-only --diff-filter=ACMR)
[ -n "$staged_files" ] || exit 0

is_governance_path() {
    case "$1" in
        AGENTS.md|CLAUDE.md|.agents/*|.claude/*|.githooks/pre-commit|scripts/check-instruction-clones.sh|scripts/check-ios-governance.sh|state/governance/current-ios-task.md)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_counted_path() {
    case "$1" in
        Flowmap/Features/*|Flowmap/DesignSystem/*|UITests/*)
            return 0
            ;;
        *)
            is_governance_path "$1"
            return $?
            ;;
    esac
}

counted=false
governance_only=true
staged_proof=false
device_sensitive=false

for path in $staged_files; do
    if [ "$path" = "$proof_file" ]; then
        staged_proof=true
    fi

    if is_counted_path "$path"; then
        counted=true
    fi

    if ! is_governance_path "$path"; then
        governance_only=false
    fi

    case "$path" in
        Flowmap/Features/Focus/*|Flowmap/Features/Map/*|Flowmap/Features/Shared/PhoneRootView.swift|Flowmap/DesignSystem/FlowMotion.swift|Flowmap/Features/Shared/QuickCapture.swift|Flowmap/Features/Shared/GlobalSearchView.swift|Flowmap/Features/*/*Sheet*.swift)
            device_sensitive=true
            ;;
    esac
done

if [ "$counted" != true ]; then
    exit 0
fi

if [ "$staged_proof" != true ]; then
    echo "Counted iOS work is staged, but $proof_file is not part of the same change set." >&2
    exit 1
fi

if [ ! -f "$proof_file" ]; then
    echo "Missing required governance proof file: $proof_file" >&2
    exit 1
fi

proof_tmp=$(mktemp)
if ! git show ":$proof_file" >"$proof_tmp"; then
    echo "Unable to read staged governance proof file: $proof_file" >&2
    exit 1
fi

if [ "$device_sensitive" != true ]; then
    staged_patch=$(git diff --cached --unified=0 --)
    if printf '%s\n' "$staged_patch" | rg -q 'DragGesture|MagnifyGesture|LongPressGesture|gesture|impactOccurred|notificationOccurred|AVAudioSession|keyboard|safeAreaInset|toolbar|tabItem|TabView|presentationDetents'; then
        device_sensitive=true
    fi
fi

python3 - "$proof_tmp" "$governance_only" "$device_sensitive" <<'PY'
import re
import sys
from pathlib import Path

proof_path = Path(sys.argv[1])
governance_only = sys.argv[2] == "true"
device_sensitive = sys.argv[3] == "true"

text = proof_path.read_text()

required_sections = [
    "Date",
    "Task Master ID",
    "Why this task counts as iOS UI work",
    "Surfaces changed",
    "Components changed",
    "Required HIG sections read",
    "Anti-patterns to avoid",
    "Constraints to satisfy",
    "Native Apple APIs/components used",
    "Verification required",
    "Evidence gathered",
    "Conflict rulings",
]

section_pattern = re.compile(r"^## (.+)$", re.MULTILINE)
matches = list(section_pattern.finditer(text))
sections = {}
for idx, match in enumerate(matches):
    name = match.group(1).strip()
    start = match.end()
    end = matches[idx + 1].start() if idx + 1 < len(matches) else len(text)
    sections[name] = text[start:end].strip()

missing = [name for name in required_sections if name not in sections or not sections[name].strip()]
if missing:
    print("Governance proof file is missing required non-empty sections:", file=sys.stderr)
    for name in missing:
        print(f"  - {name}", file=sys.stderr)
    sys.exit(1)

def parse_keys(body: str):
    pairs = {}
    for line in body.splitlines():
        line = line.strip()
        if not line.startswith("- "):
            continue
        line = line[2:]
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        pairs[key.strip()] = value.strip()
    return pairs

verification = parse_keys(sections["Verification required"])
evidence = parse_keys(sections["Evidence gathered"])
required_keys = {"code-proof", "screenshot-proof", "ax-proof", "device-proof"}

for key_set_name, payload in [("Verification required", verification), ("Evidence gathered", evidence)]:
    missing_keys = sorted(required_keys - set(payload))
    if missing_keys:
        print(f"{key_set_name} is missing required keys: {', '.join(missing_keys)}", file=sys.stderr)
        sys.exit(1)

def ensure(condition: bool, message: str):
    if not condition:
        print(message, file=sys.stderr)
        sys.exit(1)

def non_empty_required(payload: dict, key: str, section_name: str):
    value = payload.get(key, "").strip()
    ensure(value != "", f"{section_name} {key} must not be empty.")
    return value

non_empty_required(verification, "code-proof", "Verification required")
non_empty_required(evidence, "code-proof", "Evidence gathered")
non_empty_required(verification, "reason", "Verification required")

if governance_only:
    ensure(verification["code-proof"] == "required", "Governance-only work must require code-proof.")
    for key in ("screenshot-proof", "ax-proof", "device-proof"):
        ensure(verification[key] == "not-required", f"Governance-only work must mark {key} as not-required.")
        ensure(evidence[key] == "not-required", f"Governance-only work must record {key} as not-required in evidence.")
else:
    for key in ("code-proof", "screenshot-proof", "ax-proof"):
        ensure(verification[key] == "required", f"Counted UI work must require {key}.")
        ensure(evidence[key] and evidence[key] != "not-required", f"Counted UI work must gather {key} evidence.")

    if device_sensitive:
        ensure(verification["device-proof"] == "required", "Device-sensitive work must require device-proof.")
        ensure(evidence["device-proof"] and evidence["device-proof"] != "not-required", "Device-sensitive work must gather device-proof evidence.")
    else:
        ensure(verification["device-proof"] in {"required", "not-required"}, "device-proof verification value must be explicit.")
        if verification["device-proof"] == "required":
            ensure(evidence["device-proof"] and evidence["device-proof"] != "not-required", "Required device-proof must have evidence.")
        else:
            ensure(evidence["device-proof"] == "not-required", "Non-device-sensitive work must mark device-proof evidence as not-required when it is not required.")
PY
