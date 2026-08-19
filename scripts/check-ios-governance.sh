#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

proof_file="state/governance/current-ios-task.md"
proof_tmp=""
staged_patch_tmp=""

cleanup() {
    if [ -n "$proof_tmp" ] && [ -f "$proof_tmp" ]; then
        rm -f "$proof_tmp"
    fi
    if [ -n "$staged_patch_tmp" ] && [ -f "$staged_patch_tmp" ]; then
        rm -f "$staged_patch_tmp"
    fi
}

trap cleanup EXIT INT TERM

staged_files=$(git diff --cached --name-only --diff-filter=ACMR)
[ -n "$staged_files" ] || exit 0

is_governance_path() {
    case "$1" in
        AGENTS.md|CLAUDE.md|.agents/*|.claude/*|.githooks/pre-commit|.taskmaster/docs/openai-apps-design-system-prd.md|scripts/check-instruction-clones.sh|scripts/check-ios-governance.sh|state/governance/current-ios-task.md)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_counted_path() {
    case "$1" in
        Flowmap/App/*|Flowmap/Features/*|Flowmap/DesignSystem/*|Flowmap/Resources/*|FlowmapWatch/*|FlowmapWatchWidget/*|UITests/*)
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

old_ifs=$IFS
IFS='
'
for path in $staged_files; do
    if [ "$path" = "$proof_file" ]; then
        staged_proof=true
    fi

    if is_counted_path "$path"; then
        counted=true
        if ! is_governance_path "$path"; then
            governance_only=false
        fi
    fi

    case "$path" in
        Flowmap/Features/Focus/*|Flowmap/Features/Map/*|Flowmap/Features/Shared/PhoneRootView.swift|Flowmap/DesignSystem/FlowMotion.swift|Flowmap/Features/Shared/QuickCapture.swift|Flowmap/Features/Shared/GlobalSearchView.swift|Flowmap/Features/*/*Sheet*.swift)
            device_sensitive=true
            ;;
    esac
done
IFS=$old_ifs

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

staged_patch_tmp=$(mktemp)
git diff --cached --unified=0 -- >"$staged_patch_tmp"
design_policy_change=false
if rg -q 'openai-apps-design-system|openai-native-ios' "$staged_patch_tmp"; then
    design_policy_change=true
fi

if [ "$device_sensitive" != true ]; then
    if rg -q 'DragGesture|MagnifyGesture|LongPressGesture|gesture|impactOccurred|notificationOccurred|AVAudioSession|keyboard|safeAreaInset|toolbar|tabItem|TabView|presentationDetents' "$staged_patch_tmp"; then
        device_sensitive=true
    fi
fi

python3 - "$proof_tmp" "$governance_only" "$device_sensitive" "$design_policy_change" <<'PY'
import re
import sys
from pathlib import Path

proof_path = Path(sys.argv[1])
governance_only = sys.argv[2] == "true"
device_sensitive = sys.argv[3] == "true"
design_policy_change = sys.argv[4] == "true"

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
        key = key.strip()
        if key in pairs:
            print(f"Governance proof contains duplicate evidence key: {key}", file=sys.stderr)
            sys.exit(1)
        pairs[key] = value.strip()
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

def completed_evidence(payload: dict, key: str):
    value = payload.get(key, "").strip()
    ensure(value not in {"", "required", "pending"}, f"Evidence gathered {key} must contain completed evidence, not {value or 'an empty value'}.")
    ensure("pending" not in value.lower(), f"Evidence gathered {key} must not remain pending.")
    return value

non_empty_required(verification, "code-proof", "Verification required")
completed_evidence(evidence, "code-proof")
non_empty_required(verification, "reason", "Verification required")

if not governance_only or design_policy_change:
    design_section = sections.get("OpenAI Apps design-system evidence", "").strip()
    ensure(design_section != "", "Counted UI work must include an OpenAI Apps design-system evidence section.")
    design = parse_keys(design_section)
    ensure(design.get("skill") == "openai-apps-design-system", "Counted UI work must invoke openai-apps-design-system.")
    ensure(design.get("status") == "invoked", "OpenAI Apps design-system evidence status must be invoked.")
    ensure(design.get("excluded-skill") == "openai-native-ios", "Flowmap UI work must explicitly exclude openai-native-ios.")
    native_invoked = any(
        parse_keys(body).get("skill") == "openai-native-ios"
        and parse_keys(body).get("status") == "invoked"
        for body in sections.values()
    )
    ensure(not native_invoked, "Flowmap UI work must not invoke openai-native-ios.")

if governance_only:
    ensure(verification["code-proof"] == "required", "Governance-only work must require code-proof.")
    ensure("hook-proof" in evidence, "Governance-only work must record hook-proof evidence.")
    completed_evidence(evidence, "hook-proof")
    for key in ("screenshot-proof", "ax-proof", "device-proof"):
        ensure(verification[key] == "not-required", f"Governance-only work must mark {key} as not-required.")
        ensure(evidence[key] == "not-required", f"Governance-only work must record {key} as not-required in evidence.")
else:
    for key in ("code-proof", "screenshot-proof", "ax-proof"):
        ensure(verification[key] == "required", f"Counted UI work must require {key}.")
        ensure(evidence[key] and evidence[key] != "not-required", f"Counted UI work must gather {key} evidence.")
        completed_evidence(evidence, key)

    if device_sensitive:
        ensure(verification["device-proof"] == "required", "Device-sensitive work must require device-proof.")
        ensure(evidence["device-proof"] and evidence["device-proof"] != "not-required", "Device-sensitive work must gather device-proof evidence.")
        completed_evidence(evidence, "device-proof")
    else:
        ensure(verification["device-proof"] in {"required", "not-required"}, "device-proof verification value must be explicit.")
        if verification["device-proof"] == "required":
            ensure(evidence["device-proof"] and evidence["device-proof"] != "not-required", "Required device-proof must have evidence.")
            completed_evidence(evidence, "device-proof")
        else:
            ensure(evidence["device-proof"] == "not-required", "Non-device-sensitive work must mark device-proof evidence as not-required when it is not required.")
PY
