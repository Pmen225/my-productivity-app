#!/bin/sh
set -eu

project_root=${FLOWMAP_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
cd "$project_root"

private_paths='(^|/)(\.taskmaster|state|\.superdesign|Artifacts|Screenshots|Prototypes|\.agents/commands|\.agents/skills|\.claude/commands|\.claude/skills)(/|$)|(^|/)docs/course-setup-spec\.md$'
tracked_private=$(git ls-files | rg "$private_paths" | rg -v '^\.agents/skills/ship/|^\.claude/skills/ship/' || true)
if [ -n "$tracked_private" ]; then
    echo "Public policy failed: a declared private path is tracked." >&2
    exit 1
fi

if [ "$(wc -l < CLAUDE.md | tr -d ' ')" -ge 200 ]; then
    echo "Public policy failed: CLAUDE.md is not compressed below 200 lines." >&2
    exit 1
fi

if [ "$(wc -l < AGENTS.md | tr -d ' ')" -ne 1 ] || ! grep -Fqx '@CLAUDE.md' AGENTS.md; then
    echo "Public policy failed: AGENTS.md is not the single-line import entrypoint." >&2
    exit 1
fi

for forbidden in cognitive-profile '/Users/' '/home/' 'Pmen225' '\\.codex/' 'flowmap-private'; do
    if git grep -I -n -E "$forbidden" -- ':!docs/governance/current-ios-task.md' ':!scripts/check-public-policy.sh' >/dev/null 2>&1; then
        echo "Public policy failed: forbidden private marker detected." >&2
        exit 1
    fi
done

if command -v gitleaks >/dev/null 2>&1; then
    gitleaks git --no-banner --redact --exit-code 1 --log-level error .
fi
