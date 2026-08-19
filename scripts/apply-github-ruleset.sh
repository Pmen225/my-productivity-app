#!/bin/sh
set -eu

repo=${GITHUB_REPOSITORY:?Set GITHUB_REPOSITORY to owner/repository before applying the ruleset.}
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ruleset="$root/.github/rulesets/main-governance.json"

command -v gh >/dev/null 2>&1 || { echo "GitHub CLI is required." >&2; exit 1; }
[ -f "$ruleset" ] || { echo "Missing ruleset definition: $ruleset" >&2; exit 1; }

existing=$(gh api "repos/$repo/rulesets" --jq '.[] | select(.name == "main hands-off governance") | .id' | head -1 || true)
if [ -n "$existing" ]; then
    gh api --method PUT "repos/$repo/rulesets/$existing" --input "$ruleset" >/dev/null
else
    gh api --method POST "repos/$repo/rulesets" --input "$ruleset" >/dev/null
fi

echo "Active main ruleset applied to $repo."
