#!/bin/sh
set -eu

project_root=${FLOWMAP_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
project_claude=${FLOWMAP_PROJECT_CLAUDE:-$project_root/CLAUDE.md}
project_agents=${FLOWMAP_PROJECT_AGENTS:-$project_root/AGENTS.md}
global_claude=${FLOWMAP_GLOBAL_CLAUDE:-}
global_codex_agents=${FLOWMAP_GLOBAL_CODEX_AGENTS:-}

exit_code=0

compare_pair() {
    left=$1
    right=$2
    label=$3

    if [ ! -f "$left" ] || [ ! -f "$right" ]; then
        echo "$label must exist in both mirrored locations." >&2
        echo "  left : $left" >&2
        echo "  right: $right" >&2
        exit_code=1
        return
    fi

    if ! cmp -s "$left" "$right"; then
        echo "$label must be byte-for-byte identical." >&2
        diff -u "$left" "$right" >&2 || true
        exit_code=1
    fi
}

compare_tree() {
    left_root=$1
    right_root=$2
    label=$3

    left_list=$(mktemp)
    right_list=$(mktemp)
    union_list=$(mktemp)

    if [ -d "$left_root" ]; then
        find "$left_root" -type f | sed "s|$left_root/||" | sort >"$left_list"
    else
        : >"$left_list"
    fi

    if [ -d "$right_root" ]; then
        find "$right_root" -type f | sed "s|$right_root/||" | sort >"$right_list"
    else
        : >"$right_list"
    fi

    if ! cmp -s "$left_list" "$right_list"; then
        echo "$label file sets must be mirrored." >&2
        diff -u "$left_list" "$right_list" >&2 || true
        exit_code=1
    fi

    cat "$left_list" "$right_list" | sort -u >"$union_list"
    while IFS= read -r rel_path; do
        [ -n "$rel_path" ] || continue
        compare_pair "$left_root/$rel_path" "$right_root/$rel_path" "$label/$rel_path"
    done <"$union_list"

    rm -f "$left_list" "$right_list" "$union_list"
}

require_file() {
    path=$1
    label=$2

    if [ ! -f "$path" ]; then
        echo "$label is missing: $path" >&2
        exit_code=1
    fi
}

require_exactly_one_line() {
    path=$1
    expected=$2
    label=$3
    count=$(grep -Fxc -- "$expected" "$path" || true)

    if [ "$count" -ne 1 ]; then
        echo "$label must contain exactly one required line:" >&2
        echo "  $expected" >&2
        exit_code=1
    fi
}

require_single_line_file() {
    path=$1
    expected=$2
    label=$3
    expected_file=$(mktemp)
    printf '%s\n' "$expected" >"$expected_file"

    if ! cmp -s "$path" "$expected_file"; then
        echo "$label must contain exactly one line: $expected" >&2
        exit_code=1
    fi

    rm -f "$expected_file"
}

require_file "$project_claude" "Project CLAUDE.md"
require_file "$project_agents" "Project AGENTS.md"
if [ -n "$global_claude" ]; then require_file "$global_claude" "Global CLAUDE.md"; fi
if [ -n "$global_codex_agents" ]; then require_file "$global_codex_agents" "Global Codex AGENTS.md"; fi

if [ -f "$project_claude" ]; then
    claude_line_count=$(wc -l <"$project_claude" | tr -d ' ')
    if [ "$claude_line_count" -ge 200 ]; then
        echo "Project CLAUDE.md must remain under 200 lines (found $claude_line_count)." >&2
        exit_code=1
    fi
fi

require_exactly_one_line "$project_claude" '- Required UI skill: `openai-apps-design-system`; `openai-native-ios` is excluded for Flowmap.' "Project CLAUDE.md"

if [ -f "$project_agents" ]; then
    require_single_line_file "$project_agents" "@CLAUDE.md" "Project AGENTS.md"
fi

if [ -n "$global_codex_agents" ] && [ -n "$global_claude" ] && [ -f "$global_codex_agents" ] && [ -f "$global_claude" ]; then
    require_exactly_one_line "$global_codex_agents" "@$global_claude" "Global Codex AGENTS.md"
    if grep -Fqx "@$HOME/.claude/AGENTS.md" "$global_codex_agents"; then
        echo "Global Codex AGENTS.md still points to the obsolete Claude AGENTS.md clone." >&2
        exit_code=1
    fi
fi

compare_tree "$project_root/.agents/commands" "$project_root/.claude/commands" "commands"
compare_tree "$project_root/.agents/skills" "$project_root/.claude/skills" "skills"
compare_tree "$project_root/.agents/rules" "$project_root/.claude/rules" "rules"

exit "$exit_code"
