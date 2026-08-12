#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

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

compare_pair "$project_root/CLAUDE.md" "$project_root/AGENTS.md" "CLAUDE.md and AGENTS.md"
compare_tree "$project_root/.agents/commands" "$project_root/.claude/commands" "commands"
compare_tree "$project_root/.agents/skills" "$project_root/.claude/skills" "skills"

exit "$exit_code"
