#!/bin/sh
set -eu

project_root=${FLOWMAP_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
report_path=${1:-$project_root/build/compliance-report.json}
mkdir -p "$(dirname "$report_path")"
commit=$(git -C "$project_root" rev-parse HEAD)
timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
cat >"$report_path" <<EOF
{
  "repository": "Flowmap public repository",
  "commit": "$commit",
  "generatedAt": "$timestamp",
  "lessonAudit": "private companion repository",
  "readableLessons": null,
  "unavailableOrDuplicateLessons": null,
  "distribution": "merge-only; no TestFlight or App Store upload"
}
EOF
