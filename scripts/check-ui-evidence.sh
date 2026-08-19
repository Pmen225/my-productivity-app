#!/bin/sh
set -eu

project_root=${FLOWMAP_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
cd "$project_root"

test -f docs/governance/current-ios-task.md
grep -Fq 'Deterministic time' docs/governance/current-ios-task.md
grep -Fq 'Required evidence' docs/governance/current-ios-task.md
